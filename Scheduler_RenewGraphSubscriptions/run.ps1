# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
try {
    Write-LogMessage -API "Scheduler_RenewGraphSubscriptions" -tenant "none" -message "Starting Graph Subscription Renewal" -sev Info
    Invoke-CippGraphWebhookRenewal
} catch {
    Write-LogMessage -API "Scheduler_RenewGraphSubscriptions" -tenant "none" -message "Failed to renew graph subscriptions" -sev Info
}