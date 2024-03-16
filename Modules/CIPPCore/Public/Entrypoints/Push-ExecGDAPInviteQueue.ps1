function Push-ExecGDAPInviteQueue {
    # Input bindings are passed in via param block.
    param($Item)

    # Write out the queue message and metadata to the information log.
    Write-Host "PowerShell queue trigger function processed work item: $($Item.customer.displayName)"

    Set-CIPPGDAPInviteGroups -Relationship $Item
}