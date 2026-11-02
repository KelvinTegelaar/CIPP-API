# Pester tests for Invoke-ListAppPermissionExposure: input validation, the parameters passed to
# Get-CIPPAppPermissionExposure, and the status codes for upstream and missing-cache failures.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Reports/Invoke-ListAppPermissionExposure.ps1'

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPAppPermissionExposure { param($TenantFilter, [switch]$Live, [switch]$ExcludeDelegated, $ServicePrincipalId) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . $FunctionPath

    function New-Request {
        param([hashtable]$Query)
        [pscustomobject]@{ Query = [pscustomobject]$Query; Headers = @{}; Params = @{ CIPPEndpoint = 'ListAppPermissionExposure' } }
    }
}

Describe 'Invoke-ListAppPermissionExposure' {
    BeforeEach {
        Mock Get-CIPPAppPermissionExposure { [pscustomobject]@{ AppId = 'app-1' } }
        Mock Write-LogMessage {}
    }

    It 'returns 400 without a tenant' {
        $Response = Invoke-ListAppPermissionExposure -Request (New-Request @{}) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        Should -Invoke Get-CIPPAppPermissionExposure -Times 0
    }

    It 'returns 400 for AllTenants, cached or live' -ForEach @(@{ Cached = 'true' }, @{ Cached = 'false' }) {
        $Response = Invoke-ListAppPermissionExposure -Request (New-Request @{ tenantFilter = 'AllTenants'; UseReportDB = $Cached }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        Should -Invoke Get-CIPPAppPermissionExposure -Times 0
    }

    It 'reads the reporting database when asked' {
        $Response = Invoke-ListAppPermissionExposure -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; UseReportDB = 'true' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        @($Response.Body).Count | Should -Be 1
        Should -Invoke Get-CIPPAppPermissionExposure -Times 1 -Exactly -ParameterFilter { -not $Live -and $TenantFilter -eq 'contoso.onmicrosoft.com' }
    }

    It 'reads Graph live by default' {
        $null = Invoke-ListAppPermissionExposure -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com' }) -TriggerMetadata $null
        Should -Invoke Get-CIPPAppPermissionExposure -Times 1 -Exactly -ParameterFilter { $Live }
    }

    It 'passes a single service principal through' {
        $Id = '0b1f2c3d-4e5f-6071-8293-a4b5c6d7e8f9'
        $null = Invoke-ListAppPermissionExposure -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; UseReportDB = 'true'; ServicePrincipalId = $Id }) -TriggerMetadata $null
        Should -Invoke Get-CIPPAppPermissionExposure -Times 1 -Exactly -ParameterFilter { $ServicePrincipalId -eq $Id }
    }

    It 'returns 400 for a service principal id that is not a GUID' {
        $Response = Invoke-ListAppPermissionExposure -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; ServicePrincipalId = "x' or 1 eq 1" }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        Should -Invoke Get-CIPPAppPermissionExposure -Times 0
    }

    It 'returns 404 when the cache has not been collected' {
        Mock Get-CIPPAppPermissionExposure { throw [System.Management.Automation.ItemNotFoundException]::new('No ServicePrincipals data is cached') }

        $Response = Invoke-ListAppPermissionExposure -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; UseReportDB = 'true' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
    }

    It 'returns 500 for an upstream failure' {
        Mock Get-CIPPAppPermissionExposure { throw 'Graph unavailable' }

        $Response = Invoke-ListAppPermissionExposure -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com' }) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
        Should -Invoke Write-LogMessage -Times 1 -Exactly
    }
}
