# Regression tests for CyberDrain/CIPP#491 - scheduler tenant-selector filtering.
#
# A scheduled task is stored against whichever tenant identifier the caller supplied when it was
# created (customerId, default domain, or the initial .onmicrosoft.com domain). The list endpoint
# used to resolve the selected tenant to only its default domain + customerId, so a task created via
# the API against the initial domain was filtered out of the tenant view and only reappeared under
# "*AllTenants". Both the storage query filter and the allowed-tenant access check must accept all
# three identifiers.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListScheduledItems.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListScheduledItems.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stubs so Mock has commands to replace.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors, [switch]$SkipList, [switch]$IncludeAll, [switch]$TriggerRefresh, [switch]$SkipDomains, [switch]$CleanOld) }
    # Return the raw value so filter assertions are predictable (the real helper quotes/escapes).
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }

    . $FunctionPath

    $script:Contoso = [pscustomobject]@{
        customerId        = 'aaaaaaaa-1111-2222-3333-444444444444'
        defaultDomainName = 'contoso.com'                 # custom domain made default in M365
        initialDomainName = 'contoso.onmicrosoft.com'     # differs from default - the bug's trigger
    }
    $script:Fabrikam = [pscustomobject]@{
        customerId        = 'bbbbbbbb-1111-2222-3333-444444444444'
        defaultDomainName = 'fabrikam.com'
        initialDomainName = 'fabrikam.onmicrosoft.com'
    }

    function New-ListRequest {
        param($TenantFilter)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListScheduledItems' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]@{ tenantFilter = $TenantFilter }
        }
    }
}

Describe 'Invoke-ListScheduledItems tenant identifier resolution (#491)' {
    BeforeEach {
        $script:CapturedFilter = $null
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = $TableName } }
        # -TenantFilter call resolves the selected tenant; -IncludeErrors call builds the display/access lookup.
        Mock -CommandName Get-Tenants -ParameterFilter { $TenantFilter } -MockWith { $script:Contoso }
        Mock -CommandName Get-Tenants -ParameterFilter { $IncludeErrors } -MockWith { @($script:Contoso, $script:Fabrikam) }
    }

    It 'builds a storage filter that matches default domain, initial domain, and customerId' {
        Mock -CommandName Test-CIPPAccess -MockWith { 'AllTenants' }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:CapturedFilter = $Filter; @() }

        $null = Invoke-ListScheduledItems -Request (New-ListRequest -TenantFilter 'contoso.com')

        $script:CapturedFilter | Should -Match "Tenant eq 'contoso\.com'"
        $script:CapturedFilter | Should -Match "Tenant eq 'contoso\.onmicrosoft\.com'"
        $script:CapturedFilter | Should -Match "Tenant eq 'aaaaaaaa-1111-2222-3333-444444444444'"
    }

    It 'returns a task stored under the initial domain to a tenant-scoped caller' {
        # Scoped (non-AllTenants) caller: the access check must accept the initial domain too.
        Mock -CommandName Test-CIPPAccess -MockWith { @('aaaaaaaa-1111-2222-3333-444444444444') }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{ RowKey = '1'; Name = 'Task-Default'; Command = 'Invoke-CIPPOffboardingJob'; Tenant = 'contoso.com' }
                [pscustomobject]@{ RowKey = '2'; Name = 'Task-Initial'; Command = 'Invoke-CIPPOffboardingJob'; Tenant = 'contoso.onmicrosoft.com' }
                [pscustomobject]@{ RowKey = '3'; Name = 'Task-Other';   Command = 'Invoke-CIPPOffboardingJob'; Tenant = 'fabrikam.onmicrosoft.com' }
            )
        }

        $Response = Invoke-ListScheduledItems -Request (New-ListRequest -TenantFilter 'contoso.com')
        $Names = @($Response.Body.Name)

        $Names | Should -Contain 'Task-Default'
        $Names | Should -Contain 'Task-Initial'   # regressed before the fix: dropped by the access check
        $Names | Should -Not -Contain 'Task-Other'
    }
}
