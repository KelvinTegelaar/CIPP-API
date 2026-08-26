# Pester tests for Invoke-ListLicenseOptimization — single-tenant report, AllTenants money map,
# the required-tenant guard, and error handling.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListLicenseOptimization.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListLicenseOptimization.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippException { param($Exception) @{ NormalizedError = $Exception } }
    function Get-CIPPLicenseOptimization { param($TenantFilter, $InactiveDays) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-OptRequest {
        param([hashtable]$Query = @{})
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListLicenseOptimization' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]$Query
            Body    = [pscustomobject]@{}
        }
    }
}

Describe 'Invoke-ListLicenseOptimization' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { param($Exception) @{ NormalizedError = "$Exception" } }
    }

    It 'returns the full report for a single tenant' {
        Mock -CommandName Get-CIPPLicenseOptimization -MockWith {
            [pscustomobject]@{
                Summary       = [pscustomobject]@{ Tenant = $TenantFilter; ReclaimableMonthly = 100; DataAvailable = $true }
                Opportunities = @([pscustomobject]@{ Tier = 'UnassignedSeats'; MonthlySaving = 100 })
            }
        }

        $Response = Invoke-ListLicenseOptimization -Request (New-OptRequest @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.Summary.ReclaimableMonthly | Should -Be 100
        $Response.Body.Results.Opportunities.Count | Should -Be 1
        Should -Invoke Get-CIPPLicenseOptimization -Times 1 -Exactly
    }

    It 'passes the inactiveDays override through' {
        Mock -CommandName Get-CIPPLicenseOptimization -MockWith {
            [pscustomobject]@{ Summary = [pscustomobject]@{ DataAvailable = $true }; Opportunities = @() }
        }

        $null = Invoke-ListLicenseOptimization -Request (New-OptRequest @{ tenantFilter = 'contoso.com'; inactiveDays = '30' })

        Should -Invoke Get-CIPPLicenseOptimization -Times 1 -Exactly -ParameterFilter { $InactiveDays -eq 30 }
    }

    It 'returns a ranked per-tenant summary money map for AllTenants' {
        Mock -CommandName Get-Tenants -MockWith {
            @(
                [pscustomobject]@{ defaultDomainName = 'a.com' }
                [pscustomobject]@{ defaultDomainName = 'b.com' }
                [pscustomobject]@{ defaultDomainName = 'empty.com' }
            )
        }
        Mock -CommandName Get-CIPPLicenseOptimization -MockWith {
            $Map = @{ 'a.com' = 50; 'b.com' = 200; 'empty.com' = 0 }
            [pscustomobject]@{
                Summary       = [pscustomobject]@{ Tenant = $TenantFilter; ReclaimableMonthly = $Map[$TenantFilter]; DataAvailable = ($TenantFilter -ne 'empty.com') }
                Opportunities = @()
            }
        }

        $Response = Invoke-ListLicenseOptimization -Request (New-OptRequest @{ tenantFilter = 'AllTenants' })

        $Response.StatusCode | Should -Be 200
        # empty.com has no cached data and is dropped; the rest are ranked by reclaimable spend
        $Response.Body.Results.Count | Should -Be 2
        $Response.Body.Results[0].Tenant | Should -Be 'b.com'
        $Response.Body.Results[1].Tenant | Should -Be 'a.com'
    }

    It 'fails when no tenant is supplied and it is not AllTenants' {
        $Response = Invoke-ListLicenseOptimization -Request (New-OptRequest @{})

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Match 'tenantFilter is required'
    }
}
