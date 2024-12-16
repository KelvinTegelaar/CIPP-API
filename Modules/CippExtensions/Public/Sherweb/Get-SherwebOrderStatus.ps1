function Get-SherwebOrderStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionKey,
        [Parameter(Mandatory = $true)]
        [string]$RequestTrackingId
    )
    $AuthHeader = Get-SherwebAuthentication -ClientId $ClientId -ClientSecret $ClientSecret -SubscriptionKey $SubscriptionKey
    $Uri = "https://api.sherweb.com/service-provider/v1/tracking/$RequestTrackingId"
    $Tracking = Invoke-RestMethod -Uri $Uri -Method GET -Headers $AuthHeader
    return $Tracking
}
