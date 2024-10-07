function Start-CIPPGraphSubscriptionRenewalTimer {
    <#
    .SYNOPSIS
    Start the Graph Subscription Renewal Timer
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-CIPPGraphSubscriptionRenewalTimer', 'Starting Graph Subscription Renewal Timer')) {
        try {
            Write-LogMessage -API 'Scheduler_RenewGraphSubscriptions' -tenant 'none' -message 'Starting Graph Subscription Renewal' -sev Info
            Invoke-CippGraphWebhookRenewal
        } catch {
            Write-LogMessage -API 'Scheduler_RenewGraphSubscriptions' -tenant 'none' -message 'Failed to renew graph subscriptions' -sev Info
        }
    }
}
