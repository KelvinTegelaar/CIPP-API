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
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$Type,

        [Parameter(Mandatory = $false)]
        [switch]$CountsOnly
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'

        if ($CountsOnly) {
            $Filter = "PartitionKey eq '{0}'" -f $TenantFilter
            $Results = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            $Results = $Results | Where-Object { $_.RowKey -like '*-Count' }
        } else {
            if (-not $Type) {
                throw 'Type parameter is required when CountsOnly is not specified'
            }
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}.'" -f $TenantFilter, $Type
            $Results = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        }

        return $Results

    } catch {
        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Failed to get items$(if ($Type) { " of type $Type" })$(if ($CountsOnly) { ' (counts only)' }): $($_.Exception.Message)" -sev Error
        throw
    }
}
