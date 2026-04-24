function Get-CIPPTestResults {
    <#
    .SYNOPSIS
        Retrieves test results and tenant counts for a specific tenant

    .PARAMETER TenantFilter
        The tenant domain or GUID to retrieve results for

    .EXAMPLE
        Get-CIPPTestResults -TenantFilter 'contoso.onmicrosoft.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $Table = Get-CippTable -tablename 'CippTestResults'
        $Filter = "PartitionKey eq '{0}'" -f $TenantFilter
        $TestResults = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        $CountData = Get-CIPPDbItem -TenantFilter $TenantFilter -CountsOnly

        $TenantCounts = @{}
        $LatestTimestamp = ($CountData | Where-Object { $_.Timestamp } | Measure-Object -Property Timestamp -Maximum).Maximum

        foreach ($CountRow in $CountData) {
            $TypeName = $CountRow.RowKey -replace '-Count$', ''
            $TenantCounts[$TypeName] = $CountRow.DataCount
        }

        return [PSCustomObject]@{
            TestResults           = $TestResults
            TenantCounts          = $TenantCounts
            LatestReportTimeStamp = $LatestTimestamp
        }

    } catch {
        Write-LogMessage -API 'CIPPTestResults' -tenant $TenantFilter -message "Failed to get test results: $($_.Exception.Message)" -sev Error
        throw
    }
}
