# Pester tests for Invoke-ListDeviceNonCompliance: reads cached non-compliant setting rows and joins each
# device's compliance state from the ManagedDevices cache, single tenant and AllTenants.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields, $Rows) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly, [switch]$ByTenant) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CippBulkStatusCode.ps1' -File | Select-Object -First 1 -ExpandProperty FullName)

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListDeviceNonCompliance.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    function New-Request ($Tenant) { [pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = $Tenant } } }
}

Describe 'Invoke-ListDeviceNonCompliance' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock New-CIPPDbRequest -ParameterFilter { $Type -eq 'IntuneNonCompliantSettings' } {
            [pscustomobject]@{ deviceId = 'dev-1'; deviceName = 'PC1'; policyName = 'Baseline'; settingName = 'Require BitLocker' }
            [pscustomobject]@{ deviceId = 'dev-2'; deviceName = 'PC2'; policyName = 'Baseline'; settingName = 'Minimum OS' }
        }
        Mock New-CIPPDbRequest -ParameterFilter { $Type -eq 'ManagedDevices' } {
            [pscustomobject]@{ id = 'dev-1'; complianceState = 'noncompliant' }
            [pscustomobject]@{ id = 'dev-2'; complianceState = 'inGracePeriod' }
        }
        Mock Get-CIPPDbItem -ParameterFilter { $CountsOnly } { [pscustomobject]@{ Timestamp = '2026-10-29T03:00:00Z' } }
    }

    It 'requires a tenant' {
        (Invoke-ListDeviceNonCompliance -Request (New-Request $null)).StatusCode | Should -Be 400
    }

    It 'joins each row to its device compliance state and cache time' {
        $Response = Invoke-ListDeviceNonCompliance -Request (New-Request 'contoso.com')
        $Response.StatusCode | Should -Be 200
        $Response.Body.complianceState | Should -Be @('noncompliant', 'inGracePeriod')
        $Response.Body[0].CacheTimestamp | Should -Be '2026-10-29T03:00:00Z'
        Should -Invoke New-CIPPDbRequest -Times 1 -Exactly -ParameterFilter { $Type -eq 'ManagedDevices' -and ($Fields -join ',') -eq 'id,complianceState' }
    }

    It 'returns an empty list when the tenant has no failing settings' {
        Mock New-CIPPDbRequest -ParameterFilter { $Type -eq 'IntuneNonCompliantSettings' } {}
        $Response = Invoke-ListDeviceNonCompliance -Request (New-Request 'contoso.com')
        $Response.StatusCode | Should -Be 200
        @($Response.Body).Count | Should -Be 0
        Should -Invoke New-CIPPDbRequest -Times 0 -Exactly -ParameterFilter { $Type -eq 'ManagedDevices' }
    }

    It 'tags rows with their tenant for AllTenants and reports 207 when one tenant fails' {
        Mock Get-CIPPDbItem -ParameterFilter { $ByTenant } { @{ 'a.com' = @('rows-a'); 'b.com' = @('rows-b') } }
        Mock New-CIPPDbRequest -ParameterFilter { $Type -eq 'IntuneNonCompliantSettings' -and $TenantFilter -eq 'b.com' } { throw 'corrupt row' }
        $Response = Invoke-ListDeviceNonCompliance -Request (New-Request 'AllTenants')
        $Response.StatusCode | Should -Be 207
        @($Response.Body.Tenant | Select-Object -Unique) | Should -Be @('a.com')
        Should -Invoke New-CIPPDbRequest -ParameterFilter { $Type -eq 'IntuneNonCompliantSettings' -and $TenantFilter -eq 'a.com' -and $Rows -contains 'rows-a' }
    }
}
