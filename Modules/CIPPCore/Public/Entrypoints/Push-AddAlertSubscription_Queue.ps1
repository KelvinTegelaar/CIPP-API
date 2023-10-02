function Push-AddAlertSubscription_Queue {
    # Input bindings are passed in via param block.
    param($QueueItem, $TriggerMetadata)

    try {
        Write-Information ($QueueItem | ConvertTo-Json)
        New-CIPPGraphSubscription @QueueItem
        Write-Information "Added webhook subscription for $($QueueItem.TenantFilter)"
    } catch {
        Write-Error "Unable to add webhook subscription $($_.Exception.Message)"
    }

}