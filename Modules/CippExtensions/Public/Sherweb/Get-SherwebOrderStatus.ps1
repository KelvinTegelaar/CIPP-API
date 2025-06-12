function Get-SherwebOrderStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestTrackingId
    )
    $AuthHeader = Get-SherwebAuthentication
    $Uri = "https://api.sherweb.com/service-provider/v1/tracking/$RequestTrackingId"
    $Tracking = Invoke-RestMethod -Uri $Uri -Method GET -Headers $AuthHeader
    return $Tracking
}
