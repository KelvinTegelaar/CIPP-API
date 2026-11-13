function Resolve-CIPPOwningPartner {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Resolves which partner tenant owns a customer tenant.
    .DESCRIPTION
    Returns the Tenants row's partnerTenantId, defaulting to the primary partner. A partner
    tenant id resolves to itself. Private on purpose.
    .PARAMETER TenantFilter
    Customer tenant id (GUID) or default domain name.
    .PARAMETER TenantRow
    Already-fetched Tenants row for the customer; skips the table lookup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Filter')]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true, ParameterSetName = 'Row')]
        $TenantRow
    )

    if (!$env:TenantID) {
        $null = Get-CIPPAuthentication
    }

    $Flag = Get-CIPPFeatureFlag -Id 'MultiPartner'
    if (-not $Flag.Enabled) {
        return "$env:TenantID"
    }

    if ($PSCmdlet.ParameterSetName -eq 'Filter') {
        if ($TenantFilter -eq $env:TenantID) {
            return "$env:TenantID"
        }
        if (Get-CIPPPartnerTenant -PartnerTenantId $TenantFilter) {
            return $TenantFilter
        }
        $TenantsTable = Get-CippTable -tablename 'Tenants'
        $SafeFilter = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
        if ($TenantFilter -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            $Filter = "PartitionKey eq 'Tenants' and RowKey eq '{0}'" -f $SafeFilter
        } else {
            $Filter = "PartitionKey eq 'Tenants' and defaultDomainName eq '{0}'" -f $SafeFilter
        }
        $TenantRow = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter | Select-Object -First 1
    }

    if ($TenantRow.partnerTenantId) {
        return "$($TenantRow.partnerTenantId)"
    }
    return "$env:TenantID"
}
