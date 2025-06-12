function Start-CIPPGraphSubscriptionRenewalTimer {
    <#
    .SYNOPSIS
    Start the Graph Subscription Renewal Timer
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-CIPPGraphSubscriptionRenewalTimer', 'Starting Graph Subscription Renewal Timer')) {
        Invoke-CippGraphWebhookRenewal
    }
}
