BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'
    $Pim = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/PIM'

    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType, $CollectorArgs) }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CIPPPIMRoleSettings { param($TenantFilter, $PolicyId, $DesiredRules, $CurrentRules, $RoleName, $APIName) }

    foreach ($Helper in @('ConvertTo-CIPPPIMRoleSettings', 'Test-CIPPPIMRoleSettingsFloor', 'ConvertTo-CIPPPIMPolicyRules', 'Compare-CIPPPIMRoleSettings', 'Get-CIPPPrivilegedRoleTemplateIds')) {
        . (Join-Path $Pim "$Helper.ps1")
    }
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselinePIMRoleSettingsState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselinePIMRoleSettings.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:GlobalAdmin = '62e90394-69f5-4237-9190-012177145e10'
    $script:SecurityAdmin = '194ae4cb-b126-40b2-bd5b-6091b380977d'

    function New-TemplateSettings {
        param([hashtable]$Override = @{})
        $Settings = [ordered]@{
            activationMaxDuration                 = 'PT8H'
            activationRequires                    = 'MFA'
            authenticationContextClaimValue       = ''
            activationRequiresJustification       = $true
            activationRequiresTicket              = $false
            activationRequiresApproval            = $false
            approvers                             = ''
            eligibilityMaxDuration                = 'P365D'
            activeAssignmentMaxDuration           = 'P180D'
            activeAssignmentRequiresMfa           = $true
            activeAssignmentRequiresJustification = $true
            notificationRecipients                = ''
            notificationLevel                     = 'All'
        }
        foreach ($Key in $Override.Keys) { $Settings[$Key] = $Override[$Key] }
        $Settings
    }

    function New-TemplateRow {
        param([hashtable]$Override = @{}, $RoleScope = 'Privileged', $Roles = @())
        $Json = [ordered]@{ templateName = 'Tier 0'; roleScope = $RoleScope; roles = $Roles; settings = (New-TemplateSettings $Override) } | ConvertTo-Json -Depth 20
        [PSCustomObject]@{ RowKey = 'tpl-pim'; GUID = 'tpl-pim'; JSON = $Json }
    }

    # A cached policy row whose rules already match the template, as the RoleManagementPolicies cache stores it.
    function New-PolicyRow {
        param($RoleId, [scriptblock]$Mutate)
        $Rules = ConvertTo-CIPPPIMPolicyRules -Settings (ConvertTo-CIPPPIMRoleSettings -InputObject (New-TemplateSettings)) -CurrentRules @()
        $Row = [PSCustomObject]@{ roleDefinitionId = $RoleId; policyId = "policy-$RoleId"; rules = @($Rules) } | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        if ($Mutate) { & $Mutate $Row }
        $Row
    }

    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }

    $script:Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ TemplateList = [PSCustomObject]@{ label = 'Tier 0'; value = 'tpl-pim' } } }
    $script:AllPrivileged = @(Get-CIPPPrivilegedRoleTemplateIds -Set Privileged)
    $script:ValidSettings = ConvertTo-CIPPPIMRoleSettings -InputObject (New-TemplateSettings)
}

Describe 'Get-CIPPBaselinePIMRoleSettingsState' {
    BeforeEach {
        Mock New-GraphGetRequest { @() }
        Mock Write-LogMessage {}
        Mock Get-CIPPAzDataTableEntity { New-TemplateRow }
        Mock Get-CIPPBaselineCacheRows { @() }
        Mock Get-CIPPBaselineCacheRows { @(foreach ($Id in $script:AllPrivileged) { New-PolicyRow -RoleId $Id }) } -ParameterFilter { $Type -eq 'RoleManagementPolicies' }
    }

    It 'is compliant when every privileged role policy matches the template' {
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        @($Prepared.Expected.PSObject.Properties).Count | Should -Be $script:AllPrivileged.Count
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
        @($Prepared.Current.driftedRoles).Count | Should -Be 0
    }

    It 'grades the drifted role by name and carries its policy for the executor' {
        Mock Get-CIPPBaselineCacheRows {
            @(foreach ($Id in $script:AllPrivileged) {
                    if ($Id -eq $script:GlobalAdmin) {
                        New-PolicyRow -RoleId $Id -Mutate { param($Row) ($Row.rules | Where-Object id -EQ 'Expiration_EndUser_Assignment').maximumDuration = 'PT24H' }
                    } else { New-PolicyRow -RoleId $Id }
                })
        } -ParameterFilter { $Type -eq 'RoleManagementPolicies' }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        $Verdict = Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current
        $Verdict.Count | Should -Be 1
        $Prepared.Current.'Global Administrator' | Should -Match 'Expiration_EndUser_Assignment'
        $Drifted = @($Prepared.Current.driftedRoles)
        $Drifted.Count | Should -Be 1
        $Drifted[0].PolicyId | Should -Be "policy-$($script:GlobalAdmin)"
        @($Drifted[0].Desired).Count | Should -BeGreaterThan 0
    }

    It 'grades a covered role with no PIM policy as drift' {
        Mock Get-CIPPBaselineCacheRows { @(foreach ($Id in $script:AllPrivileged) { if ($Id -ne $script:SecurityAdmin) { New-PolicyRow -RoleId $Id } }) } -ParameterFilter { $Type -eq 'RoleManagementPolicies' }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Current.'Security Administrator' | Should -Be 'No PIM policy for this role'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 1
        @($Prepared.Current.driftedRoles)[0].PolicyId | Should -BeNullOrEmpty
    }

    It 'grades only the listed roles for a Custom scope' {
        Mock Get-CIPPAzDataTableEntity { New-TemplateRow -RoleScope 'Custom' -Roles @(@{ label = 'Global Administrator'; value = $script:GlobalAdmin }) }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        @($Prepared.Expected.PSObject.Properties.Name) | Should -Be @('Global Administrator')
    }

    It 'grades every cached policy for an AllRoles scope' {
        Mock Get-CIPPAzDataTableEntity { New-TemplateRow -RoleScope 'AllRoles' }
        Mock Get-CIPPBaselineCacheRows { @((New-PolicyRow -RoleId $script:GlobalAdmin), (New-PolicyRow -RoleId 'custom-role')) } -ParameterFilter { $Type -eq 'RoleManagementPolicies' }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        @($Prepared.Expected.PSObject.Properties.Name) | Should -Be @('Global Administrator', 'custom-role')
    }

    It 'reports No Data, never Compliant, when the template cannot be resolved' {
        Mock Get-CIPPAzDataTableEntity { }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -Match 'could not be found'
    }

    It 'refuses a template below the secure floor' {
        Mock Get-CIPPAzDataTableEntity { New-TemplateRow -Override @{ activationMaxDuration = 'PT25H' } }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -Match 'secure floor'
    }

    It 'reports No Data when PIM has no cached policies' {
        Mock Get-CIPPBaselineCacheRows { @() } -ParameterFilter { $Type -eq 'RoleManagementPolicies' }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -Match 'onboarded'
    }

    It 'refuses an approval template when no approver resolves in the tenant' {
        Mock Get-CIPPAzDataTableEntity { New-TemplateRow -Override @{ activationRequiresApproval = $true; approvers = 'nobody@contoso.com' } }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -Match 'approvers'
    }

    It 'resolves UPN approvers to users and names to groups before grading' {
        Mock Get-CIPPAzDataTableEntity { New-TemplateRow -Override @{ activationRequiresApproval = $true; approvers = 'boss@contoso.com; Tier0 Approvers' } }
        Mock Get-CIPPBaselineCacheRows { @([PSCustomObject]@{ id = 'u0'; userPrincipalName = 'other@contoso.com' }, [PSCustomObject]@{ id = 'u1'; userPrincipalName = 'Boss@Contoso.com' }) } -ParameterFilter { $Type -eq 'Users' }
        Mock Get-CIPPBaselineCacheRows { @([PSCustomObject]@{ id = 'g1'; displayName = 'Tier0 Approvers' }, [PSCustomObject]@{ id = 'g2'; displayName = 'Tier0 Approvers' }) } -ParameterFilter { $Type -eq 'Groups' }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Current | Should -Not -BeNullOrEmpty
        $Approval = @($Prepared.Current.driftedRoles)[0].Desired | Where-Object { $_['id'] -eq 'Approval_EndUser_Assignment' }
        $Json = $Approval | ConvertTo-Json -Depth 20
        $Json | Should -Match '"userId": "u1"'
        $Json | Should -Match '"groupId": "g1"'
        $Json | Should -Not -Match '"g2"'
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'reads only the Users cache when every approver is a UPN' {
        Mock Get-CIPPAzDataTableEntity { New-TemplateRow -Override @{ activationRequiresApproval = $true; approvers = 'boss@contoso.com' } }
        Mock Get-CIPPBaselineCacheRows { @([PSCustomObject]@{ id = 'u1'; userPrincipalName = 'boss@contoso.com' }) } -ParameterFilter { $Type -eq 'Users' }
        $null = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        Should -Invoke Get-CIPPBaselineCacheRows -Times 0 -ParameterFilter { $Type -eq 'Groups' }
    }

    It 'names roles from the RoleDefinitions cache without a live read' {
        Mock Get-CIPPAzDataTableEntity { New-TemplateRow -RoleScope 'AllRoles' }
        Mock Get-CIPPBaselineCacheRows { @((New-PolicyRow -RoleId 'custom-role')) } -ParameterFilter { $Type -eq 'RoleManagementPolicies' }
        Mock Get-CIPPBaselineCacheRows { @([PSCustomObject]@{ id = 'custom-role'; templateId = 'custom-role'; displayName = 'Helpdesk Lite' }) } -ParameterFilter { $Type -eq 'RoleDefinitions' }
        $Prepared = Get-CIPPBaselinePIMRoleSettingsState -Item $script:Item -TenantFilter $script:Tenant
        @($Prepared.Expected.PSObject.Properties.Name) | Should -Be @('Helpdesk Lite')
        Should -Invoke New-GraphGetRequest -Times 0
    }
}

Describe 'Invoke-CIPPBaselinePIMRoleSettings' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Set-CIPPPIMRoleSettings { @([PSCustomObject]@{ Success = $true }) }
    }

    It 'patches each drifted role with its desired and current rules and skips roles without a policy' {
        $Current = [PSCustomObject]@{
            templateName = 'Tier 0'; templateSettings = $script:ValidSettings
            driftedRoles = @(
                [PSCustomObject]@{ Role = 'Global Administrator'; PolicyId = 'p-ga'; Desired = @(@{ id = 'r1' }); Rules = @(@{ id = 'r1' }) }
                [PSCustomObject]@{ Role = 'Security Administrator'; PolicyId = $null; Desired = $null; Rules = $null }
            )
        }
        Invoke-CIPPBaselinePIMRoleSettings -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPPIMRoleSettings -Times 1 -Exactly -ParameterFilter { $PolicyId -eq 'p-ga' -and $RoleName -eq 'Global Administrator' -and $DesiredRules[0].id -eq 'r1' -and $TenantFilter -eq $script:Tenant }
    }

    It 'throws when every write failed' {
        Mock Set-CIPPPIMRoleSettings { @([PSCustomObject]@{ Success = $false }) }
        $Current = [PSCustomObject]@{ templateName = 'Tier 0'; templateSettings = $script:ValidSettings; driftedRoles = @([PSCustomObject]@{ Role = 'Global Administrator'; PolicyId = 'p-ga'; Desired = @(); Rules = @() }) }
        { Invoke-CIPPBaselinePIMRoleSettings -Remediate $null -TenantFilter $script:Tenant -Current $Current } | Should -Throw '*every drifted role*'
    }

    It 'does not throw when only some writes failed' {
        Mock Set-CIPPPIMRoleSettings { @([PSCustomObject]@{ Success = $false }) } -ParameterFilter { $PolicyId -eq 'p-ga' }
        $Current = [PSCustomObject]@{
            templateName = 'Tier 0'; templateSettings = $script:ValidSettings
            driftedRoles = @(
                [PSCustomObject]@{ Role = 'Global Administrator'; PolicyId = 'p-ga'; Desired = @(); Rules = @() }
                [PSCustomObject]@{ Role = 'Security Administrator'; PolicyId = 'p-sa'; Desired = @(); Rules = @() }
            )
        }
        { Invoke-CIPPBaselinePIMRoleSettings -Remediate $null -TenantFilter $script:Tenant -Current $Current } | Should -Not -Throw
    }

    It 'throws when no drifted role has a policy to write' {
        $Current = [PSCustomObject]@{ templateName = 'Tier 0'; templateSettings = $script:ValidSettings; driftedRoles = @([PSCustomObject]@{ Role = 'Security Administrator'; PolicyId = $null }) }
        { Invoke-CIPPBaselinePIMRoleSettings -Remediate $null -TenantFilter $script:Tenant -Current $Current } | Should -Throw '*No PIM policy exists*'
        Should -Invoke Set-CIPPPIMRoleSettings -Times 0 -Exactly
    }

    It 'refuses to write settings below the secure floor' {
        $Weak = ConvertTo-CIPPPIMRoleSettings -InputObject (New-TemplateSettings @{ activationMaxDuration = 'PT25H' })
        $Current = [PSCustomObject]@{ templateName = 'Tier 0'; templateSettings = $Weak; driftedRoles = @([PSCustomObject]@{ Role = 'Global Administrator'; PolicyId = 'p-ga'; Desired = @(); Rules = @() }) }
        { Invoke-CIPPBaselinePIMRoleSettings -Remediate $null -TenantFilter $script:Tenant -Current $Current } | Should -Throw '*secure floor*'
        Should -Invoke Set-CIPPPIMRoleSettings -Times 0 -Exactly
    }
}
