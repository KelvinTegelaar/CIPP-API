function Remove-Pax8Subscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string[]]$SubscriptionIds,
        [string]$TenantFilter,
        $Headers
    )

    Test-Pax8LicenseRole -Headers $Headers

    foreach ($SubscriptionId in $SubscriptionIds) {
        Invoke-Pax8Request -Method DELETE -Path "subscriptions/$SubscriptionId" -NoContent | Out-Null
    }

    return [PSCustomObject]@{
        Results = "Cancelled $($SubscriptionIds.Count) Pax8 subscription(s)."
    }
}
