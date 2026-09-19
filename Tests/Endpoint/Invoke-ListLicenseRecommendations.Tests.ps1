# Pester tests for Invoke-ListLicenseRecommendations — parameter parsing, the single-tenant guard,
# and error handling.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListLicenseRecommendations.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListLicenseRecommendations.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippException { param($Exception) @{ NormalizedError = $Exception } }
    function Get-CIPPLicenseRecommendation { param($TenantFilter, $Currency, $InactiveDays, $TenureMonths, $RecommendDowngrades, $RecommendUpgrades, $RecommendTerms, $ProtectSecurityFeatures) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-RecRequest {
        param([hashtable]$Query = @{})
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListLicenseRecommendations' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]$Query
            Body    = [pscustomobject]@{}
        }
    }
}

Describe 'Invoke-ListLicenseRecommendations' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { param($Exception) @{ NormalizedError = "$Exception" } }
        Mock -CommandName Get-CIPPLicenseRecommendation -MockWith {
            [pscustomobject]@{ Summary = [pscustomobject]@{ Tenant = $TenantFilter; TotalPotentialMonthly = 42 }; Downgrades = @(); Upgrades = @(); Terms = @() }
        }
    }

    It 'returns the report with default settings' {
        $Response = Invoke-ListLicenseRecommendations -Request (New-RecRequest @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.Summary.TotalPotentialMonthly | Should -Be 42
        Should -Invoke Get-CIPPLicenseRecommendation -Times 1 -Exactly -ParameterFilter {
            $TenantFilter -eq 'contoso.com' -and $Currency -eq 'USD' -and $InactiveDays -eq 90 -and $TenureMonths -eq 6 -and
            $RecommendDowngrades -eq $true -and $RecommendUpgrades -eq $true -and $RecommendTerms -eq $true -and $ProtectSecurityFeatures -eq $true
        }
    }

    It 'passes switches, thresholds and currency through' {
        $null = Invoke-ListLicenseRecommendations -Request (New-RecRequest @{
                tenantFilter = 'contoso.com'; currency = 'EUR'; inactiveDays = '30'; tenureMonths = '9'
                recommendDowngrades = 'false'; recommendUpgrades = 'true'; recommendTerms = 'false'; protectSecurityFeatures = 'false'
            })

        Should -Invoke Get-CIPPLicenseRecommendation -Times 1 -Exactly -ParameterFilter {
            $Currency -eq 'EUR' -and $InactiveDays -eq 30 -and $TenureMonths -eq 9 -and
            $RecommendDowngrades -eq $false -and $RecommendUpgrades -eq $true -and $RecommendTerms -eq $false -and $ProtectSecurityFeatures -eq $false
        }
    }

    It 'rejects AllTenants and a missing tenant' {
        (Invoke-ListLicenseRecommendations -Request (New-RecRequest @{ tenantFilter = 'AllTenants' })).StatusCode | Should -Be 500
        (Invoke-ListLicenseRecommendations -Request (New-RecRequest @{})).StatusCode | Should -Be 500
        Should -Invoke Get-CIPPLicenseRecommendation -Times 0
    }

    It 'returns 500 with the error text when the report fails' {
        Mock -CommandName Get-CIPPLicenseRecommendation -MockWith { throw 'boom' }

        $Response = Invoke-ListLicenseRecommendations -Request (New-RecRequest @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match 'boom'
        Should -Invoke Write-LogMessage -Times 1 -Exactly
    }
}
