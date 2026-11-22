# Anonymous callers pick the TenantId, so an unknown one must never reach Get-Tenants -TenantFilter,
# which rebuilds the tenant list from GDAP on a customerId miss.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) }
    function Get-CIPPTable { param($tablename) @{} }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data, [switch]$Append) }
    function Write-AlertMessage { param($message, $sev, $tenant) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTenantLookup.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-PublicPhishingCheck.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    function New-Request {
        param([hashtable]$Body)
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'PublicPhishingCheck' }; Headers = @{}; Body = [pscustomobject]$Body }
    }
}

Describe 'PublicPhishingCheck tenant lookup' {
    BeforeEach {
        Mock Get-Tenants { [pscustomobject]@{ customerId = '11111111-1111-1111-1111-111111111111'; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com' } }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Write-AlertTrace { }
        Mock Write-AlertMessage { }
    }

    It 'stores nothing and never filters Get-Tenants for an unknown tenant' {
        $Response = Invoke-PublicPhishingCheck -Request (New-Request @{ TenantId = '99999999-9999-9999-9999-999999999999'; source = 'ext'; Cloned = $true })
        $Response.StatusCode | Should -Be 200
        Should -Invoke Get-Tenants -Times 0 -ParameterFilter { $TenantFilter }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        Should -Invoke Write-AlertMessage -Times 0
    }

    It 'stores the alert against a known tenant' -ForEach @(
        @{ TenantId = '11111111-1111-1111-1111-111111111111' }
        @{ TenantId = 'contoso.onmicrosoft.com' }
    ) {
        Invoke-PublicPhishingCheck -Request (New-Request @{ TenantId = $TenantId; source = 'ext' }) | Out-Null
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.tenantFilter -eq 'contoso.com' }
    }

    It 'raises a cloned-site alert for a known customerId' {
        Invoke-PublicPhishingCheck -Request (New-Request @{ TenantId = '11111111-1111-1111-1111-111111111111'; Cloned = $true; AlertMessage = 'clone' }) | Out-Null
        Should -Invoke Write-AlertMessage -Times 1
    }
}
