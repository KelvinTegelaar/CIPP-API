# An All Tenants licence report read from the cache returns only the tenants in the caller's scope, whichever
# filter (QueueId or recent rows) picked the cache rows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListLicensesReport.ps1' -File)[0].FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { [CmdletBinding()] param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($TableName, $Filter) }
    function ConvertTo-CIPPODataFilterValue { [CmdletBinding()] param($Value) $Value }
    function Get-Tenants { [CmdletBinding()] param([switch]$IncludeErrors) }

    . $FunctionPath
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPCore') -Recurse -Filter 'Select-CippAllowedTenantData.ps1' -File)[0].FullName

    $script:Alpha = [pscustomobject]@{ defaultDomainName = 'alpha.onmicrosoft.com'; customerId = 'aaaa-1111' }
    $script:Rows = foreach ($Domain in 'alpha.onmicrosoft.com', 'beta.onmicrosoft.com') {
        [pscustomobject]@{ RowKey = $Domain; QueueId = 'q1'; License = (@(@{ Tenant = $Domain; License = 'E3' }) | ConvertTo-Json -Compress -AsArray) }
    }
}

Describe 'Invoke-ListLicensesReport for a tenant-restricted caller' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { $script:Rows }
        # The request scope holds alpha; Get-Tenants is narrowed to it, as it is under the router
        Mock Get-Tenants { $script:Alpha }
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('aaaa-1111') }
    }
    AfterEach { $script:CippAllowedTenantsStorage = $null }

    It 'returns only allowed tenants for a <Name> read' -ForEach @(
        @{ Name = 'QueueId'; Query = @{ tenantFilter = 'AllTenants'; QueueId = 'q1' } }
        @{ Name = 'recent rows'; Query = @{ tenantFilter = 'AllTenants' } }
    ) {
        $Body = (Invoke-ListLicensesReport -Request ([pscustomobject]@{ Query = [pscustomobject]$Query }) -TriggerMetadata $null).Body
        @($Body.Results.Tenant) | Should -Be @('alpha.onmicrosoft.com')
    }

    It 'adds the tenant display name, falling back to the domain' {
        $Query = [pscustomobject]@{ tenantFilter = 'AllTenants' }
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'alpha.onmicrosoft.com'; customerId = 'aaaa-1111'; displayName = 'Alpha Billing Name' } }
        $Body = (Invoke-ListLicensesReport -Request ([pscustomobject]@{ Query = $Query }) -TriggerMetadata $null).Body
        $Body.Results[0].TenantName | Should -Be 'Alpha Billing Name'

        Mock Get-Tenants { $script:Alpha }
        $Body = (Invoke-ListLicensesReport -Request ([pscustomobject]@{ Query = $Query }) -TriggerMetadata $null).Body
        $Body.Results[0].TenantName | Should -Be 'alpha.onmicrosoft.com'
    }
}
