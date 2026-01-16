function New-CIPPDbRequest {
    <#
    .SYNOPSIS
        Query the CIPP Reporting database by partition key

    .DESCRIPTION
        Retrieves data from the CippReportingDB table filtered by partition key (tenant)

    .PARAMETER TenantFilter
        The tenant domain or GUID to filter by (used as partition key)

    .PARAMETER Type
        Optional. The data type to filter by (e.g., Users, Groups, Devices)

    .EXAMPLE
        New-CIPPDbRequest -TenantFilter 'contoso.onmicrosoft.com'

    .EXAMPLE
        New-CIPPDbRequest -TenantFilter 'contoso.onmicrosoft.com' -Type 'Users'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$Type
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'

        if ($Type) {
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}.'" -f $TenantFilter, $Type
        } else {
            $Filter = "PartitionKey eq '{0}'" -f $TenantFilter
        }

        $Results = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        return ($Results.Data | ConvertFrom-Json -ErrorAction SilentlyContinue)
    } catch {
        Write-LogMessage -API 'CIPPDbRequest' -tenant $TenantFilter -message "Failed to query database: $($_.Exception.Message)" -sev Error
        throw
    }
}
