BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Format-CIPPCAPolicy.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Remove-ODataProperties.ps1')

    function Get-CIPPTextReplacement { [CmdletBinding()] param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function New-GraphPOSTRequest {
        [CmdletBinding()] param($uri, $tenantid, $type, $body, $asApp, $ScheduleRetry)
        $script:GraphWrites.Add(@{ Uri = $uri; Type = $type; Body = $body })
        [pscustomobject]@{ id = 'created-policy-id' }
    }
    function New-GraphGETRequest { [CmdletBinding()] param($uri, $tenantid, $asApp, [switch]$ComplexFilter) throw "Unexpected live Graph GET in test: $uri" }
    function New-GraphBulkRequest { [CmdletBinding()] param($Requests, $tenantid, $asapp) @() }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $TenantFilter, $Headers, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPTable { [CmdletBinding()] param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($filter) @() }
    function Start-Sleep { [CmdletBinding()] param($Seconds) }
    function Get-CIPPTenantCapabilities { [CmdletBinding()] param($TenantFilter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Sync-CIPPGSAFilteringProfile { [CmdletBinding()] param($ProfileTemplate, $PolicyTemplates, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPCAPolicy.ps1')

    $script:TenantProfileId = '33333333-3333-3333-3333-333333333333'
    function Get-Template([hashtable]$SessionControls) {
        [ordered]@{
            displayName     = 'Web filtering for staff'
            state           = 'disabled'
            conditions      = @{ users = @{ includeUsers = @('All') }; applications = @{ includeApplications = @('All') }; clientAppTypes = @('all') }
            grantControls   = @{ operator = 'OR'; builtInControls = @('mfa') }
            sessionControls = $SessionControls
        } | ConvertTo-Json -Depth 10
    }
    function Invoke-Deploy([string]$RawJSON) {
        $script:GraphWrites = [System.Collections.Generic.List[object]]::new()
        $null = New-CIPPCAPolicy -RawJSON $RawJSON -TenantFilter 'contoso.com' -State 'disabled' -Overwrite $true -PreloadedCAPolicies @([pscustomobject]@{ id = 'other'; displayName = 'Unrelated' })
        $Write = $script:GraphWrites.Where({ $_.Uri -eq 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' })[-1]
        $Write.Body | ConvertFrom-Json
    }
}

Describe 'New-CIPPCAPolicy with a Global Secure Access security profile session control' {
    It 'sends a tenant security profile id unchanged' {
        $Body = Invoke-Deploy (Get-Template @{ globalSecureAccessFilteringProfile = @{ profileId = $script:TenantProfileId; isEnabled = $true } })
        $Body.sessionControls.globalSecureAccessFilteringProfile.profileId | Should -Be $script:TenantProfileId
        $Body.sessionControls.globalSecureAccessFilteringProfile.isEnabled | Should -BeTrue
    }

    It 'keeps a disabled session control and the other session controls as they are' {
        $Body = Invoke-Deploy (Get-Template @{ globalSecureAccessFilteringProfile = @{ profileId = $script:TenantProfileId; isEnabled = $false }; signInFrequency = @{ value = 4; type = 'hours'; isEnabled = $true } })
        $Body.sessionControls.globalSecureAccessFilteringProfile.isEnabled | Should -BeFalse
        $Body.sessionControls.signInFrequency.value | Should -Be 4
    }

    It 'makes no Graph or table reads, licence check or sync for a tenant profile id' {
        Mock Get-CIPPAzDataTableEntity {}
        Mock Get-CIPPTenantCapabilities {}
        Mock Sync-CIPPGSAFilteringProfile {}
        { Invoke-Deploy (Get-Template @{ globalSecureAccessFilteringProfile = @{ profileId = $script:TenantProfileId; isEnabled = $true } }) } | Should -Not -Throw
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
        Should -Invoke Get-CIPPTenantCapabilities -Times 0
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 0
    }

    It 'drops the networkAccessSecurity mirror when the security profile control is set' {
        $Body = Invoke-Deploy (Get-Template @{ globalSecureAccessFilteringProfile = @{ profileId = $script:TenantProfileId; isEnabled = $true }; networkAccessSecurity = @{ policyId = 'stale'; isEnabled = $true } })
        $Body.sessionControls.PSObject.Properties.Name | Should -Not -Contain 'networkAccessSecurity'
        $Body.sessionControls.globalSecureAccessFilteringProfile.profileId | Should -Be $script:TenantProfileId
    }
}

Describe 'New-CIPPCAPolicy with a security profile given by display name' {
    BeforeAll {
        $script:NamedTemplate = Get-Template @{ globalSecureAccessFilteringProfile = @{ profileId = 'Staff'; isEnabled = $true } }
    }
    BeforeEach {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $true } }
        Mock New-GraphGETRequest { @([pscustomobject]@{ id = $script:TenantProfileId; name = 'Staff' }, [pscustomobject]@{ id = 'other'; name = 'Guests' }) } -ParameterFilter { $uri -eq 'https://graph.microsoft.com/beta/networkAccess/filteringProfiles' }
    }

    It 'replaces the name with the id of the tenant profile of that name' {
        $Body = Invoke-Deploy $script:NamedTemplate
        $Body.sessionControls.globalSecureAccessFilteringProfile.profileId | Should -Be $script:TenantProfileId
        Should -Invoke New-GraphGETRequest -Times 1 -ParameterFilter { $asApp -eq $true -and $tenantid -eq 'contoso.com' }
    }

    It 'refuses a name the tenant has no profile for, and changes nothing' {
        $Template = Get-Template @{ globalSecureAccessFilteringProfile = @{ profileId = 'Contractors'; isEnabled = $true } }
        { Invoke-Deploy $Template } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "Security profile 'Contractors' used by policy 'Web filtering for staff' was not found in contoso.com*"
        $script:GraphWrites.Count | Should -Be 0
    }

    It 'refuses a name more than one tenant profile has' {
        Mock New-GraphGETRequest { @([pscustomobject]@{ id = 'a'; name = 'Staff' }, [pscustomobject]@{ id = 'b'; name = 'Staff' }) } -ParameterFilter { $uri -eq 'https://graph.microsoft.com/beta/networkAccess/filteringProfiles' }
        { Invoke-Deploy $script:NamedTemplate } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "2 security profiles are named 'Staff'*"
        $script:GraphWrites.Count | Should -Be 0
    }

    It 'refuses without an Internet Access licence before reading the profiles' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $false } }
        { Invoke-Deploy $script:NamedTemplate } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "*'Staff', which needs a Microsoft Entra Internet Access licence*"
        Should -Invoke New-GraphGETRequest -Times 0 -ParameterFilter { $uri -like '*filteringProfiles*' }
    }
}

Describe 'New-CIPPCAPolicy with a linked security profile template' {
    BeforeAll {
        $script:LinkedTemplate = Get-Template @{ globalSecureAccessFilteringProfile = @{ profileId = @{ label = 'Staff'; value = 'tpl-staff' }; isEnabled = $true }; networkAccessSecurity = @{ policyId = 'stale'; isEnabled = $true } }
    }
    BeforeEach {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $true } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'tpl-staff'; JSON = '{"name":"Staff","priority":1000,"policies":[{"policy":{"label":"Block risky","value":"tpl-block"},"priority":100}]}' } } -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = 'tpl-block'; JSON = '{"name":"Block risky","action":"block"}' } } -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        Mock Sync-CIPPGSAFilteringProfile { [pscustomobject]@{ ProfileId = $script:TenantProfileId; Results = @([pscustomobject]@{ state = 'success'; resultText = "Created security profile 'Staff'" }) } }
    }

    It 'deploys the security profile template, then sends the tenant profile id' {
        $Body = Invoke-Deploy $script:LinkedTemplate
        $Body.sessionControls.globalSecureAccessFilteringProfile.profileId | Should -Be $script:TenantProfileId
        $Body.sessionControls.PSObject.Properties.Name | Should -Not -Contain 'networkAccessSecurity'
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $ProfileTemplate.name -eq 'Staff' -and $PolicyTemplates['tpl-block'].name -eq 'Block risky' }
    }

    It 'refuses without an Internet Access licence and changes nothing' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ Entra_Premium_Internet_Access = $false } }
        { Invoke-Deploy $script:LinkedTemplate } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "*'Staff', which needs a Microsoft Entra Internet Access licence*"
        Should -Invoke Sync-CIPPGSAFilteringProfile -Times 0
        $script:GraphWrites.Count | Should -Be 0
    }

    It 'reports a security profile template that no longer exists as not found' {
        Mock Get-CIPPAzDataTableEntity {} -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        { Invoke-Deploy $script:LinkedTemplate } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "*template 'Staff', which no longer exists"
        $script:GraphWrites.Count | Should -Be 0
    }

    It 'does not deploy the policy when the security profile only partly deployed' {
        Mock Sync-CIPPGSAFilteringProfile { [pscustomobject]@{ ProfileId = $script:TenantProfileId; Results = @([pscustomobject]@{ state = 'error'; resultText = "Failed to deploy filtering policy 'Block risky': Graph said no" }) } }
        { Invoke-Deploy $script:LinkedTemplate } | Should -Throw -ExpectedMessage "*did not deploy fully: Failed to deploy filtering policy 'Block risky': Graph said no"
        $script:GraphWrites.Count | Should -Be 0
    }
}
