BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests/ZTNA/Identity/Invoke-CippTestZTNA21816.ps1')

    $script:GA = '62e90394-69f5-4237-9190-012177145e10'
    function New-Member($Id, $Type = 'user') { [pscustomobject]@{ '@odata.type' = "#microsoft.graph.$Type"; id = $Id; displayName = "Name $Id"; userPrincipalName = "$Id@contoso.com" } }
    function Get-CippDbRole { param($TenantFilter, [switch]$IncludePrivilegedRoles) @() }
    function Get-CippDbRoleMembers { param($TenantFilter, $RoleTemplateId) if ($RoleTemplateId -eq $script:GA) { $script:GAMembers } }
    function Get-CIPPTestData {
        param($TenantFilter, $Type, $Fields, [switch]$Stream)
        switch ($Type) {
            'RoleEligibilitySchedules' { $script:Eligible }
            'RoleAssignmentScheduleInstances' { @() }
            'Users' { $script:Users }
            'Groups' { $script:Groups }
        }
    }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
}

Describe 'ZTNA21816 Global Administrator via group' {
    BeforeEach {
        $script:Users = @(
            [pscustomobject]@{ id = 'u1'; displayName = 'User 1'; userPrincipalName = 'u1@contoso.com'; onPremisesSyncEnabled = $null }
            [pscustomobject]@{ id = 'u2'; displayName = 'User 2'; userPrincipalName = 'u2@contoso.com'; onPremisesSyncEnabled = $null }
            [pscustomobject]@{ id = 'u3'; displayName = 'User 3'; userPrincipalName = 'u3@contoso.com'; onPremisesSyncEnabled = $true }
            [pscustomobject]@{ id = 'u4'; displayName = 'User 4'; userPrincipalName = 'u4@contoso.com'; onPremisesSyncEnabled = $null }
        )
        $script:Groups = @(
            [pscustomobject]@{ id = 'g-eligible'; members = @((New-Member 'u1'), (New-Member 'u2'), (New-Member 'g-nested' 'group')) }
            [pscustomobject]@{ id = 'g-permanent'; members = @(New-Member 'u3') }
            [pscustomobject]@{ id = 'g-other'; members = @(New-Member 'u4') }
        )
        $script:Eligible = @([pscustomobject]@{ roleDefinitionId = $script:GA; principalId = 'g-eligible' })
        $script:GAMembers = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-permanent'; displayName = 'GA group'; userPrincipalName = $null })
    }

    It 'counts the user members of a group eligible for Global Administrator' {
        Invoke-CippTestZTNA21816 -Tenant 'contoso.com'
        $script:Result.Markdown | Should -Match '\| Eligible Global Administrators \| 2 \|'
        $script:Result.Markdown | Should -Not -Match 'PIM usage cannot be confirmed'
    }

    It 'lists the user members of a group permanently assigned Global Administrator' {
        Invoke-CippTestZTNA21816 -Tenant 'contoso.com'
        $script:Result.Markdown | Should -Match '\| Permanent Global Administrator users \| 1 \|'
        $script:Result.Markdown | Should -Match '\| u3@contoso\.com \| Via Group \| True \|'
        $script:Result.Markdown | Should -Not -Match 'u4@contoso\.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'reports no PIM usage when no Global Administrator eligibility exists' {
        $script:Eligible = @()
        Invoke-CippTestZTNA21816 -Tenant 'contoso.com'
        $script:Result.Markdown | Should -Match 'PIM usage cannot be confirmed'
        $script:Result.Status | Should -Be 'Failed'
    }
}
