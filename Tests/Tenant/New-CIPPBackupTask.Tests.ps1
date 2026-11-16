BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $NoAuthCheck) }
    function Measure-CippTask { [CmdletBinding()] param($TaskName, $EventName, $Script) & $Script }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPBackupTask.ps1')
}

Describe 'New-CIPPBackupTask users' {
    BeforeEach {
        Mock New-GraphGetRequest {
            @(
                [pscustomobject][ordered]@{ id = '1'; displayName = 'Adele'; mail = 'adele@contoso.com'; onPremisesSyncEnabled = $true; createdDateTime = '2024-01-01'; city = $null; passwordProfile = @{ x = 1 }; assignedPlans = @(); usageLocation = 'AU' }
                [pscustomobject][ordered]@{ id = '2'; displayName = 'Megan'; externalUserState = 'Accepted'; identities = @(); city = 'Perth'; securityIdentifier = 'S-1' }
            )
        }
    }

    It 'drops excluded properties, keeps the rest in order including nulls' {
        $Users = @(New-CIPPBackupTask -Task 'users' -TenantFilter 'contoso.onmicrosoft.com')
        $Users.Count | Should -Be 2
        $Users[0].PSObject.Properties.Name -join ',' | Should -Be 'id,displayName,city,usageLocation'
        $Users[0].PSObject.Properties['city'].Value | Should -BeNullOrEmpty
        $Users[1].PSObject.Properties.Name -join ',' | Should -Be 'id,displayName,city'
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -eq 'https://graph.microsoft.com/beta/users?$top=999' }
    }
}
