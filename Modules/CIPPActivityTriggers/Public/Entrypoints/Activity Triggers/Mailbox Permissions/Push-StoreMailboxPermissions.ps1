function Push-StoreMailboxPermissions {
    <#
    .SYNOPSIS
        Post-execution function to aggregate and store all mailbox and calendar permissions

    .DESCRIPTION
        Collects results from all batches and stores them in the reporting database

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $Results = $Item.Results

    try {
        Write-Information "Storing mailbox and calendar permissions for tenant $TenantFilter"
        Write-Information "Received $($Results.Count) batch results"

        # A batch result is normally the cmdlet-keyed hashtable, but an activity may return
        # [hashtable, "status message"] - take the hashtable and ignore anything else.
        $Unwrap = {
            param($BatchResult)
            $Actual = if ($BatchResult -is [array] -and $BatchResult.Count -gt 0) { $BatchResult[0] } else { $BatchResult }
            if ($Actual -and ($Actual -is [hashtable] -or $Actual -is [System.Collections.IDictionary])) { $Actual }
        }

        # Grouped by cmdlet name due to ReturnWithCommand. Mailbox, recipient and
        # send-on-behalf rows all land in the same MailboxPermissions type.
        $MailboxCmdlets = 'Get-MailboxPermission', 'Get-RecipientPermission', 'Get-Mailbox'

        # Count before writing. This pass only walks references that already live in
        # $Item.Results, so it costs nothing next to the write; what it buys is the decision
        # not to run a writer at all for a type with no rows. Add-CIPPDbItem's end block
        # always writes the -Count row when -AddCount is present, so an unconditional
        # pipeline would stamp a fresh count of 0 - without clearing the data rows - whenever
        # every batch failed, and the freshness gates that read count rows (see
        # Wait-CIPPBaselineCacheReady) would treat a stale cache as current.
        $MailboxRows = 0
        $CalendarRows = 0
        foreach ($BatchResult in $Results) {
            $ActualResult = & $Unwrap $BatchResult
            if (-not $ActualResult) { continue }

            foreach ($Cmdlet in $MailboxCmdlets) {
                foreach ($Row in @($ActualResult[$Cmdlet])) {
                    if ($null -ne $Row) { $MailboxRows++ }
                }
            }
            foreach ($Row in @($ActualResult['Get-MailboxFolderPermission'])) {
                if ($null -ne $Row) { $CalendarRows++ }
            }
        }

        # Rows are emitted straight into Add-CIPPDbItem rather than collected first.
        #
        # This used to build four Lists, then a fifth combining three of them, and hold all of it
        # alongside $Item.Results - which is already the whole tenant's permission set - until both
        # writes had finished. On a large tenant that is every permission record pinned twice over,
        # and it showed: this job was one of two that took a production instance to 3.8GB.
        #
        # Feeding a script block into one pipeline keeps the peak at a single batch's rows, because
        # Add-CIPPDbItem flushes every 100 and never accumulates. ONE invocation per Type is required,
        # not merely tidier: its end block runs a single orphan cleanup keyed to the run id from its
        # begin block and writes the -Count row once, so splitting the flush would have each later
        # call treat rows the earlier ones just wrote as orphans (see Set-CIPPDBCacheDefenderCVEs).
        if ($MailboxRows -gt 0) {
            & {
                foreach ($BatchResult in $Results) {
                    $ActualResult = & $Unwrap $BatchResult
                    if (-not $ActualResult) { continue }

                    foreach ($Cmdlet in $MailboxCmdlets) {
                        foreach ($Row in @($ActualResult[$Cmdlet])) {
                            if ($null -ne $Row) { $Row }
                        }
                    }
                }
            } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions' -AddCount

            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $MailboxRows mailbox permission records" -sev Info
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No mailbox permissions found to cache' -sev Info
        }

        if ($CalendarRows -gt 0) {
            & {
                foreach ($BatchResult in $Results) {
                    $ActualResult = & $Unwrap $BatchResult
                    if (-not $ActualResult) { continue }

                    foreach ($Row in @($ActualResult['Get-MailboxFolderPermission'])) {
                        if ($null -ne $Row) { $Row }
                    }
                }
            } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CalendarPermissions' -AddCount

            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $CalendarRows calendar permission records" -sev Info
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No calendar permissions found to cache' -sev Info
        }

        return

    } catch {
        $ErrorMsg = "Failed to store mailbox permissions for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
