function Push-CIPPAlertQuotaUsed {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )


    try {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')?`$format=application/json" -tenantid $QueueItem.tenant | ForEach-Object {
            if ($_.StorageUsedInBytes -eq 0) { continue }
            $PercentLeft = [math]::round($_.StorageUsedInBytes / $_.prohibitSendReceiveQuotaInBytes * 100)
            if ($PercentLeft -gt 95) { 
                Write-AlertMessage -tenant $($QueueItem.tenant) -message "$($_.UserPrincipalName): Mailbox has less than 5% space left. Mailbox is $PercentLeft% full" 
            }
        }
    } catch {
    }
}
