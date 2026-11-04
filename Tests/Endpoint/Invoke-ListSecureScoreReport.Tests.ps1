# Pester tests for Invoke-ListSecureScoreReport
#
# The endpoint is AnyTenant (so AllTenants is reachable), which means the framework's per-tenant
# check is skipped. The ControlName branch reads one tenant's cached control profile straight from
# the table, so it has to validate its input and scope access itself; these tests lock both, plus
# the includeControls passthrough of the shared Catalog.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListSecureScoreReport.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListSecureScoreReport.ps1 under Modules/' }

    $CippSharp = Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll'
    Add-Type -Path $CippSharp -ErrorAction SilentlyContinue

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPSecureScoreReport { param($TenantFilter, [switch]$IncludeHistory, [switch]$IncludeControls) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:TenantAccess }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')

    function script:Invoke-Report([hashtable]$Query) {
        Invoke-ListSecureScoreReport -Request ([pscustomobject]@{ Query = $Query }) -TriggerMetadata ([pscustomobject]@{ FunctionName = 'ListSecureScoreReport' })
    }
}

Describe 'Invoke-ListSecureScoreReport ControlName branch' {
    BeforeEach {
        $script:TenantAccess = @('AllTenants')
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'alpha.onmicrosoft.com'; customerId = 'alpha-id' } }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ RowKey = 'SecureScoreControlProfiles-MFARegistrationV2'; Data = '{"id":"MFARegistrationV2","remediation":"<p>Do it</p>"}' }
        }
    }

    It 'returns the cached profile for a valid control' {
        $Response = script:Invoke-Report @{ tenantFilter = 'alpha.onmicrosoft.com'; ControlName = 'MFARegistrationV2' }

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results.remediation | Should -Be '<p>Do it</p>'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Filter -like "PartitionKey eq 'alpha.onmicrosoft.com' and RowKey ge 'SecureScoreControlProfiles-MFARegistrationV2'*"
        }
    }

    It 'rejects a control name that could break out of the filter' {
        $Response = script:Invoke-Report @{ tenantFilter = 'alpha.onmicrosoft.com'; ControlName = "x' or PartitionKey ne '" }

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }

    It 'rejects AllTenants for a single profile read' {
        $Response = script:Invoke-Report @{ tenantFilter = 'AllTenants'; ControlName = 'MFARegistrationV2' }

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'forbids a scoped user reading a tenant outside their list' {
        $script:TenantAccess = @('other-id')
        $Response = script:Invoke-Report @{ tenantFilter = 'alpha.onmicrosoft.com'; ControlName = 'MFARegistrationV2' }

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }
}

Describe 'Invoke-ListSecureScoreReport includeControls' {
    BeforeEach {
        $script:TenantAccess = @('alpha-id')
        Mock Get-CIPPSecureScoreReport {
            [pscustomobject]@{
                Results = @(
                    [pscustomobject]@{ Tenant = 'alpha.onmicrosoft.com'; TenantId = 'alpha-id'; Controls = @() }
                    [pscustomobject]@{ Tenant = 'beta.onmicrosoft.com'; TenantId = 'beta-id'; Controls = @() }
                )
                Catalog = @{ MFARegistrationV2 = @{ title = 'Require MFA' } }
            }
        }
    }

    It 'returns the catalog and scopes the tenant rows' {
        $Response = script:Invoke-Report @{ tenantFilter = 'AllTenants'; includeControls = 'true' }

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body.Results).Tenant | Should -Be @('alpha.onmicrosoft.com')
        $Response.Body.Catalog.MFARegistrationV2.title | Should -Be 'Require MFA'
        Should -Invoke Get-CIPPSecureScoreReport -Times 1 -ParameterFilter { $IncludeControls }
    }
}
