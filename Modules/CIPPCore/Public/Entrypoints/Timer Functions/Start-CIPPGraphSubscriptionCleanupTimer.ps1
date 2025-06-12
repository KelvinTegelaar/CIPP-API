function Start-CIPPGraphSubscriptionCleanupTimer {
    <#
    .SYNOPSIS
    Remove CIPP Graph Subscriptions for all tenants except the partner tenant.

    .DESCRIPTION
    Remove CIPP Graph Subscriptions for all tenants except the partner tenant.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    try {
        $Tenants = Get-Tenants -IncludeAll | Where-Object { $_.customerId -ne $env:TenantID -and $_.Excluded -eq $false }
        $Tenants | ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.defaultDomainName, 'Remove-CIPPGraphSubscription')) {
                Remove-CIPPGraphSubscription -cleanup $true -TenantFilter $_.defaultDomainName
            }
        }
    } catch {}
}
