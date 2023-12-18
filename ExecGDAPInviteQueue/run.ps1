# Input bindings are passed in via param block.
param( $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $($QueueItem.customer.displayName)"

Set-CIPPGDAPInviteGroups -Relationship $QueueItem