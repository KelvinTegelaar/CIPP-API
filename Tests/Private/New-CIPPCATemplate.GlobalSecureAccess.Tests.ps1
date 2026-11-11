BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPCATemplate.ps1')

    $script:ProfileId = '33333333-3333-3333-3333-333333333333'
    $script:UserId = '44444444-4444-4444-4444-444444444444'
    function Invoke-Capture([hashtable]$SessionControls) {
        $Policy = [pscustomobject]@{
            displayName     = 'Staff web filtering'
            conditions      = [pscustomobject]@{ users = [pscustomobject]@{ includeUsers = @($script:UserId) }; applications = [pscustomobject]@{ includeApplications = @('All') } }
            sessionControls = [pscustomobject]$SessionControls
        }
        New-CIPPCATemplate -TenantFilter 'contoso.com' -JSON $Policy -preloadedUsers @([pscustomobject]@{ id = $script:UserId; displayName = 'Alex Wilber' }) -preloadedGroups @([pscustomobject]@{ id = 'g'; displayName = 'g' }) | ConvertFrom-Json
    }
}

Describe 'New-CIPPCATemplate with a Global Secure Access security profile session control' {
    BeforeEach {
        Mock New-GraphGetRequest {}
    }

    It 'stores users by display name, the way CA templates refer to directory objects' {
        (Invoke-Capture @{}).conditions.users.includeUsers | Should -Be @('Alex Wilber')
    }

    It 'stores the security profile by display name and drops the networkAccessSecurity mirror' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:ProfileId; name = 'Staff' } }
        $Template = Invoke-Capture @{ globalSecureAccessFilteringProfile = [pscustomobject]@{ profileId = $script:ProfileId; isEnabled = $true }; networkAccessSecurity = [pscustomobject]@{ policyId = $script:ProfileId; isEnabled = $true } }
        $Template.sessionControls.globalSecureAccessFilteringProfile.profileId | Should -Be 'Staff'
        $Template.sessionControls.globalSecureAccessFilteringProfile.isEnabled | Should -BeTrue
        $Template.sessionControls.PSObject.Properties.Name | Should -Not -Contain 'networkAccessSecurity'
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like "*/networkAccess/filteringProfiles/$($script:ProfileId)" -and $AsApp -eq $true -and $tenantid -eq 'contoso.com' }
    }

    It 'keeps the id when the security profile cannot be read, as it does for an unmatched user' {
        Mock New-GraphGetRequest { throw 'Not found' }
        (Invoke-Capture @{ globalSecureAccessFilteringProfile = [pscustomobject]@{ profileId = $script:ProfileId; isEnabled = $true } }).sessionControls.globalSecureAccessFilteringProfile.profileId | Should -Be $script:ProfileId
    }

    It 'leaves a security profile that is already a name alone' {
        (Invoke-Capture @{ globalSecureAccessFilteringProfile = [pscustomobject]@{ profileId = 'Staff'; isEnabled = $true } }).sessionControls.globalSecureAccessFilteringProfile.profileId | Should -Be 'Staff'
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'reads nothing from Graph for a policy without the control' {
        $null = Invoke-Capture @{ signInFrequency = [pscustomobject]@{ value = 4; type = 'hours'; isEnabled = $true } }
        Should -Invoke New-GraphGetRequest -Times 0
    }
}
