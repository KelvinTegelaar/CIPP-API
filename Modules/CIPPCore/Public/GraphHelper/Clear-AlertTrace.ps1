function Clear-AlertTrace {
    <#
    .FUNCTIONALITY
    Internal function. Removes the stored AlertLastRun state for an alert so a resolved alert stops showing as active.
    #>
    param(
        $CmdletName,
        $TenantFilter
    )
    $Table = Get-CIPPTable -tablename AlertLastRun
    # Delete every partition for this alert, not just today's: date-partitioned rows from
    # earlier runs and the fixed partitions (BreachAlert, SecureScore) all key on this RowKey.
    # Only rows carrying LogData are trace rows - Get-CIPPAlertCheckExtension keeps its
    # last-run watermark in this table under the same RowKey format, and that must survive.
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($TenantFilter)-$($CmdletName)'"
    $TraceRows = @($Rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.LogData) })
    if ($TraceRows.Count -gt 0) {
        Remove-AzDataTableEntity -Force @Table -Entity $TraceRows | Out-Null
        Write-Information "Cleared AlertLastRun state for cmdlet '$CmdletName' and tenant '$TenantFilter' ($($TraceRows.Count) row(s))."
    }
}
