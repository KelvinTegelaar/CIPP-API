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
            if ($QueueItem.value -eq $true) {
                if ($PercentLeft -gt 90) { 
                    Write-AlertMessage -tenant $($QueueItem.tenant) -message "$($_.UserPrincipalName): Mailbox is more than $($QueueItem.value)% full. Mailbox is $PercentLeft% full" 
                }
            }
            elseif ($PercentLeft -gt $QueueItem.value) { 
                Write-AlertMessage -tenant $($QueueItem.tenant) -message "$($_.UserPrincipalName): Mailbox is more than $($QueueItem.value)% full. Mailbox is $PercentLeft% full" 
            }
        }
    } catch {
    }
}
