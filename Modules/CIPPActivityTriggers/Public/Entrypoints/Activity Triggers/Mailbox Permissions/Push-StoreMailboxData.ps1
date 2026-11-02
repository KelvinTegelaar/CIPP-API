function Push-StoreMailboxData {
    <#
    .SYNOPSIS
        Post-execution for one stage of a tenant's chained mailbox data collection

    .DESCRIPTION
        Stores the stage's type (permissions, calendar permissions or rules), then starts the next
        stage. The next stage starts even when storing fails, so one bad type never blocks the rest.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Parameters = $Item.Parameters
    # Failed batches return no result; storing the rest would delete their mailboxes' cached rows.
    $Missing = [int]$Parameters.Batches - @($Item.Results).Count
    try {
        if ($Missing -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $Parameters.TenantFilter -message "$Missing of $($Parameters.Batches) $($Parameters.Type) batches failed; preserving the previous cache" -sev Warning
        } elseif ($Parameters.Type -eq 'Rules') {
            Push-StoreMailboxRules -Item $Item
        } else {
            Push-StoreMailboxPermissions -Item $Item
        }
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $Parameters.TenantFilter -message "Failed to store $($Parameters.Type): $($_.Exception.Message)" -sev Error
    }

    $Remaining = @(@($Parameters.Remaining).Where({ $_ }))
    if ($Remaining.Count -gt 0) {
        Start-CIPPMailboxDataStage -TenantFilter $Parameters.TenantFilter -Types $Remaining -QueueId $Parameters.QueueId
    }
}
