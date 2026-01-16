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
        [switch]$CountsOnly
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'

        if ($CountsOnly) {
            $Conditions = [System.Collections.Generic.List[string]]::new()
            if ($TenantFilter -ne 'allTenants') {
                $Conditions.Add("PartitionKey eq '{0}'" -f $TenantFilter)
            }
            if ($Type) {
                $Conditions.Add("RowKey ge '{0}-' and RowKey lt '{0}.'" -f $Type)
            }
            $Filter = [string]::Join(' and ', $Conditions)
            $Results = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property 'PartitionKey', 'RowKey', 'DataCount', 'Timestamp'
            $Results = $Results | Where-Object { $_.RowKey -like '*-Count' } | Select-Object PartitionKey, RowKey, DataCount, Timestamp
        } else {
            if (-not $Type) {
                throw 'Type parameter is required when CountsOnly is not specified'
            }
            if ($TenantFilter -ne 'allTenants') {
                $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}.'" -f $TenantFilter, $Type
            } else {
                $Filter = "RowKey ge '{0}-' and RowKey lt '{0}.'" -f $Type
            }
            $Results = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        }

        return $Results

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to get items$(if ($Type) { " of type $Type" })$(if ($CountsOnly) { ' (counts only)' }): $($_.Exception.Message)" -sev Error
        throw
    }
}

