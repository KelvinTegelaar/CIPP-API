function Set-SherwebLicenseQuantity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory = $true)]
        [int]$NewQuantity
    )

    $AuthHeader = Get-SherwebAuthentication
    $Body = ConvertTo-Json -Depth 10 -InputObject @{
        subscriptionAmendmentParameters = @(
            @{
                subscriptionId = $SubscriptionId
                newQuantity    = $NewQuantity
            }
        )
    }

    $Uri = "https://api.sherweb.com/service-provider/v1/billing/subscriptions/amendments?customerId=$CustomerId"
    $Update = Invoke-RestMethod -Uri $Uri -Method POST -Headers $AuthHeader -Body $Body -ContentType 'application/json'
    return $Update
}
