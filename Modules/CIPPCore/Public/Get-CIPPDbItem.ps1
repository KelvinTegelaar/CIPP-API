function Get-CIPPDbItem {
    <#
    .SYNOPSIS
        Get specific items from the CIPP Reporting database

    .DESCRIPTION
        Retrieves items from the CippReportingDB table using partition key (tenant) and type

    .PARAMETER TenantFilter
        The tenant domain or GUID (partition key)

    .PARAMETER Type
        The type of data to retrieve (used in row key filter)

    .PARAMETER CountsOnly
        If specified, returns all count rows for the tenant

    .EXAMPLE
        Get-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -Type 'Groups'

    .EXAMPLE
        Get-CIPPDbItem -TenantFilter 'contoso.onmicrosoft.com' -CountsOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$Type,

        [Parameter(Mandatory = $false)]
        [switch]$CountsOnly,

        # With -CountsOnly: also return each collection's recorded Shape (fields and types).
        [Parameter(Mandatory = $false)]
        [switch]$IncludeShape,

        # Return the data rows grouped by tenant (ordered: domain -> rows), managed tenants only.
        [Parameter(Mandatory = $false)]
        [switch]$ByTenant,

        # A default domain already resolved through Get-Tenants: reads that partition without another tenant lookup.
        [string]$Partition,

        [string]$TableName = 'CippReportingDB'
    )

    try {
        # Enforce tenant lock when running inside custom script execution
        if ($script:CIPPLockedTenant) {
            $TenantFilter = $script:CIPPLockedTenant
            $Partition = $null
        }

        $Table = Get-CippTable -tablename $TableName

        # $null = whole table; a scoped caller asking for allTenants reads only the tenants it may see
        $Partitions = $null
        if ($Partition) {
            $TenantFilter = $Partition
            $Partitions = @($Partition)
        } elseif ($TenantFilter -ne 'allTenants') {
            $Tenant = Get-Tenants -TenantFilter $TenantFilter
            if (-not $Tenant) {
                throw "Tenant '$TenantFilter' not found"
            }
            $TenantFilter = $Tenant.defaultDomainName
            $Partitions = @($TenantFilter)
        } elseif (($script:CippAllowedTenantsStorage -and $null -ne $script:CippAllowedTenantsStorage.Value) -or ($CountsOnly -and $Type)) {
            # One count row per tenant is a key lookup each; a RowKey-only filter scans the whole table
            $Partitions = @((Get-Tenants -IncludeErrors).defaultDomainName | Where-Object { $_ })
        } elseif ($ByTenant) {
            # A RowKey-only filter scans the whole table; one range read per managed tenant uses the partition index
            $Partitions = [string[]]@((Get-Tenants -IncludeErrors).defaultDomainName | Where-Object { $_ })
            [Array]::Sort($Partitions, [StringComparer]::Ordinal)
        }

        $Query = @{}
        # Type and partition reach the filter as literals; unescaped quotes would let a caller leave its partition
        $SafeType = ConvertTo-CIPPODataFilterValue -Value $Type -Type String
        if ($CountsOnly) {
            # Exact match for the count row when a type is given, otherwise every count row
            $RowFilter = if ($Type) { "RowKey eq '{0}-Count'" -f $SafeType } else { 'DataCount ge 0' }
            $Query.Property = @('PartitionKey', 'RowKey', 'DataCount', 'Timestamp'; if ($IncludeShape) { 'Shape' })
        } else {
            if (-not $Type) {
                throw 'Type parameter is required when CountsOnly is not specified'
            }
            $RowFilter = "RowKey ge '{0}-' and RowKey lt '{0}.'" -f $SafeType
        }

        $Results = if ($null -eq $Partitions) {
            Get-CIPPAzDataTableEntity @Table @Query -Filter $RowFilter
        } else {
            foreach ($Partition in $Partitions) {
                Get-CIPPAzDataTableEntity @Table @Query -Filter ("PartitionKey eq '{0}' and {1}" -f (ConvertTo-CIPPODataFilterValue -Value $Partition -Type String), $RowFilter)
            }
        }

        if ($ByTenant) {
            $Grouped = [ordered]@{}
            foreach ($Row in $Results) {
                if ($Row.RowKey -eq "$Type-Count") { continue }
                if (-not $Grouped.Contains($Row.PartitionKey)) { $Grouped[$Row.PartitionKey] = [System.Collections.Generic.List[object]]::new() }
                $Grouped[$Row.PartitionKey].Add($Row)
            }
            return $Grouped
        }

        return $Results

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to get items$(if ($Type) { " of type $Type" })$(if ($CountsOnly) { ' (counts only)' }): $($_.Exception.Message)" -sev Error
        throw
    }
}

