function New-CIPPDbRequest {
    <#
    .SYNOPSIS
        Query the CIPP Reporting database by partition key

    .DESCRIPTION
        Retrieves data from the CippReportingDB table filtered by partition key (tenant)

    .PARAMETER TenantFilter
        The tenant domain or GUID to filter by (used as partition key)

    .EXAMPLE
        New-CIPPDbRequest -TenantFilter 'contoso.onmicrosoft.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $Table = Get-CippTable -tablename 'CippReportingDB'
        $Filter = "PartitionKey eq '{0}'" -f $TenantFilter
        $Results = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        return $Results
    } catch {
        Write-LogMessage -API 'CIPPDbRequest' -tenant $TenantFilter `
            -message "Failed to query database: $($_.Exception.Message)" -sev Error
        throw
    }
}
