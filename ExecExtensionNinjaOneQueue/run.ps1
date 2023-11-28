# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell NinjaOne queue trigger function processed work item: $($QueueItem.NinjaAction)"


Switch ($QueueItem.NinjaAction) {
    'StartAutoMapping' { Invoke-NinjaOneOrgMapping }
    'AutoMapTenant' { Invoke-NinjaOneOrgMappingTenant -QueueItem $QueueItem } 
    'SyncTenant' { Invoke-NinjaOneTenantSync -QueueItem $QueueItem }
}
