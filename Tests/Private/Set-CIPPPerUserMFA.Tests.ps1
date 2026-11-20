BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPPerUserMFA.ps1')

    function New-GraphBulkRequest { param($tenantid, $scope, $Requests, $asapp) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
}

Describe 'Set-CIPPPerUserMFA' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'patches each user by escaped id and reports success when every request succeeds' {
        Mock -CommandName New-GraphBulkRequest -MockWith { @($Requests).ForEach({ [PSCustomObject]@{ id = $_.id; status = 204 } }) }

        $Result = Set-CIPPPerUserMFA -TenantFilter 'contoso.onmicrosoft.com' -userId 'id-1', 'guest_x.com#EXT#@contoso.onmicrosoft.com' -State 'enforced'

        $Result | Should -BeLike 'Successfully set*enforced*'
        Should -Invoke -CommandName New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            @($Requests).url -contains 'users/id-1/authentication/requirements' -and
            @($Requests).url -contains 'users/guest_x.com%23EXT%23%40contoso.onmicrosoft.com/authentication/requirements'
        }
    }

    It 'throws with the failing users when Graph rejects some of the requests' {
        Mock -CommandName New-GraphBulkRequest -MockWith {
            [PSCustomObject]@{ id = '0'; status = 204 }
            [PSCustomObject]@{ id = '1'; status = 400; body = [PSCustomObject]@{ error = [PSCustomObject]@{ message = 'More than one users found' } } }
        }

        { Set-CIPPPerUserMFA -TenantFilter 'contoso.onmicrosoft.com' -userId 'id-1', 'id-2', 'id-3' -State 'enforced' } |
            Should -Throw '*Failed for 2 of 3 users. id-2: More than one users found; id-3: no response from Graph*'
    }
}
