# Pester tests for Invoke-ListDetectedApps and Invoke-ListDetectedAppDevices: the cached DetectedApps
# list (single tenant, AllTenants and paged) and the per-app device list from the cache or live Graph.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly, [switch]$ByTenant) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields, $PageSize) }
    function Get-CIPPReportPage { param($TenantFilter, $Type, $PageSize, $ContinuationToken, $Report) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function New-GraphGetRequest { param($uri, $Tenantid) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    foreach ($Helper in 'Get-CippErrorStatusCode.ps1', 'ConvertTo-CIPPODataFilterValue.ps1', 'Get-CippBulkStatusCode.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Helper -File | Select-Object -First 1 -ExpandProperty FullName)
    }

    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/Applications'
    foreach ($File in 'Invoke-ListDetectedApps.ps1', 'Invoke-ListDetectedAppDevices.ps1') {
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $Folder $File) -Raw)))
    }

    function New-Request ([hashtable]$Query) { [pscustomobject]@{ Query = [pscustomobject]$Query } }
}

Describe 'Invoke-ListDetectedApps' {
    BeforeEach {
        Mock Get-CIPPDbItem -ParameterFilter { $CountsOnly } { [pscustomobject]@{ RowKey = 'DetectedApps-Count'; DataCount = 2; Timestamp = '2026-11-16T03:00:00Z' } }
        Mock New-CIPPDbRequest {
            [pscustomobject]@{ id = 'app-1'; displayName = 'Java 8 Update 401'; version = '8.0.4010'; deviceCount = 2 }
            [pscustomobject]@{ id = 'app-2'; displayName = 'Microsoft Edge'; version = '131.0'; deviceCount = 5 }
        }
    }

    It 'requires a tenant' {
        (Invoke-ListDetectedApps -Request (New-Request @{})).StatusCode | Should -Be 400
    }

    It 'reads the cached summary fields without the device lists' {
        $Response = Invoke-ListDetectedApps -Request (New-Request @{ tenantFilter = 'contoso.com'; UseReportDB = 'true' })
        $Response.StatusCode | Should -Be 200
        $Response.Body.id | Should -Be @('app-1', 'app-2')
        $Response.Body[0].CacheTimestamp | Should -Be '2026-11-16T03:00:00Z'
        Should -Invoke New-CIPPDbRequest -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'DetectedApps' -and $Fields -notcontains 'managedDevices' -and $Fields -contains 'deviceCount' -and $PageSize -gt 0
        }
    }

    It 'returns 404 when the tenant has no cached detected apps' {
        Mock Get-CIPPDbItem -ParameterFilter { $CountsOnly } {}
        $Response = Invoke-ListDetectedApps -Request (New-Request @{ tenantFilter = 'contoso.com'; UseReportDB = 'true' })
        $Response.StatusCode | Should -Be 404
        Should -Invoke New-CIPPDbRequest -Times 0 -Exactly
    }

    It 'tags AllTenants rows with their tenant and skips tenants without a cache' {
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'a.com' }; [pscustomobject]@{ defaultDomainName = 'b.com' } }
        Mock Get-CIPPDbItem -ParameterFilter { $CountsOnly -and $TenantFilter -eq 'b.com' } {}
        $Response = Invoke-ListDetectedApps -Request (New-Request @{ tenantFilter = 'AllTenants' })
        $Response.StatusCode | Should -Be 200
        @($Response.Body).Count | Should -Be 2
        @($Response.Body.Tenant | Select-Object -Unique) | Should -Be @('a.com')
    }

    It 'returns 207 with the readable tenants when one tenant cache read fails' {
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'a.com' }; [pscustomobject]@{ defaultDomainName = 'b.com' } }
        Mock New-CIPPDbRequest -ParameterFilter { $TenantFilter -eq 'b.com' } { throw 'storage unavailable' }
        Mock Write-LogMessage {}
        $Response = Invoke-ListDetectedApps -Request (New-Request @{ tenantFilter = 'AllTenants' })
        $Response.StatusCode | Should -Be 207
        @($Response.Body.Tenant | Select-Object -Unique) | Should -Be @('a.com')
    }

    It 'pages AllTenants through the report page helper' {
        Mock Get-CIPPReportPage { [pscustomobject]@{ Results = @(& $Report 'a.com'); Metadata = @{} } }
        $Response = Invoke-ListDetectedApps -Request (New-Request @{ tenantFilter = 'AllTenants'; manualPagination = 'true' })
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.id | Should -Be @('app-1', 'app-2')
        Should -Invoke Get-CIPPReportPage -Times 1 -Exactly -ParameterFilter { $Type -eq 'DetectedApps' }
    }

    It 'escapes the device id in the live per-device read' {
        Mock New-GraphGetRequest {}
        $null = Invoke-ListDetectedApps -Request (New-Request @{ tenantFilter = 'contoso.com'; DeviceID = '../users' })
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/managedDevices/..%2Fusers/detectedApps' }
    }
}

Describe 'Invoke-ListDetectedAppDevices' {
    BeforeEach {
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'contoso.com' } }
        Mock Get-CIPPTable { @{ Context = 'reporting' } }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{
                Data = '{"id":"app-1","displayName":"Java 8","managedDevices":[{"id":"dev-1","deviceName":"PC1","platform":"Windows","userPrincipalName":"amy@contoso.com"},{"id":"dev-2","deviceName":"PC2","platform":"Windows"}]}'
            }
        }
        Mock New-CIPPDbRequest -ParameterFilter { $Type -eq 'ManagedDevices' } {
            [pscustomobject]@{ id = 'dev-1'; azureADDeviceId = 'aad-1'; complianceState = 'compliant'; lastSyncDateTime = '2026-11-16T08:00:00Z'; operatingSystem = 'Windows' }
        }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'dev-9'; deviceName = 'LIVE1' } }
    }

    It 'requires an app id and a single tenant' {
        (Invoke-ListDetectedAppDevices -Request (New-Request @{ tenantFilter = 'contoso.com' })).StatusCode | Should -Be 400
        (Invoke-ListDetectedAppDevices -Request (New-Request @{ tenantFilter = 'AllTenants'; AppID = 'app-1' })).StatusCode | Should -Be 400
    }

    It 'reads the cached device list and fills in the Entra device id' {
        $Response = Invoke-ListDetectedAppDevices -Request (New-Request @{ tenantFilter = 'contoso.com'; AppID = 'app-1'; UseReportDB = 'true' })
        $Response.StatusCode | Should -Be 200
        $Response.Body.deviceName | Should -Be @('PC1', 'PC2')
        $Response.Body[0].azureADDeviceId | Should -Be 'aad-1'
        $Response.Body[0].complianceState | Should -Be 'compliant'
        $Response.Body[1].azureADDeviceId | Should -BeNullOrEmpty
        $Response.Body[1].operatingSystem | Should -Be 'Windows'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey eq 'contoso.com' and RowKey eq 'DetectedApps-app-1'" }
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'sanitises the row key the way the cache writer does' {
        $null = Invoke-ListDetectedAppDevices -Request (New-Request @{ tenantFilter = 'contoso.com'; AppID = "a/b'c"; UseReportDB = 'true' })
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey eq 'contoso.com' and RowKey eq 'DetectedApps-a_b''c'" }
    }

    It 'returns 404 when the app is not in the cache' {
        Mock Get-CIPPAzDataTableEntity {}
        (Invoke-ListDetectedAppDevices -Request (New-Request @{ tenantFilter = 'contoso.com'; AppID = 'app-x'; UseReportDB = 'true' })).StatusCode | Should -Be 404
    }

    It 'reads live devices from Graph and still answers without a managed device cache' {
        Mock New-CIPPDbRequest -ParameterFilter { $Type -eq 'ManagedDevices' } { throw 'no cache' }
        $Response = Invoke-ListDetectedAppDevices -Request (New-Request @{ tenantFilter = 'contoso.com'; AppID = 'app/1' })
        $Response.StatusCode | Should -Be 200
        $Response.Body[0].deviceName | Should -Be 'LIVE1'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/detectedApps/app%2F1/managedDevices' }
    }

    It 'returns 500 when Graph fails' {
        Mock New-GraphGetRequest { throw 'Forbidden' }
        (Invoke-ListDetectedAppDevices -Request (New-Request @{ tenantFilter = 'contoso.com'; AppID = 'app-1' })).StatusCode | Should -Be 500
    }
}
