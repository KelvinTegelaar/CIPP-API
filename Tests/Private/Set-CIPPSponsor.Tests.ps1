BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPSponsor.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Set-CIPPSponsor.ps1 at $FunctionPath" }

    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }

    . $FunctionPath
}

Describe 'Set-CIPPSponsor' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = 204 } }
        }
    }

    It 'adds the sponsor with a POST to the sponsors reference' {
        $Result = Set-CIPPSponsor -Users 'ada@contoso.com' -Sponsor 'grace@contoso.com' -TenantFilter 'contoso.com'

        $Result.Success | Should -BeTrue
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            $tenantid -eq 'contoso.com' -and @($Requests).Count -eq 1 -and
            $Requests[0].method -eq 'POST' -and $Requests[0].url -eq 'users/ada@contoso.com/sponsors/$ref'
        }
    }
}
