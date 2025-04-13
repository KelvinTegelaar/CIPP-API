function Get-TenantIdFromSubscriptionId {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    # Full credit goes to Jos Lieben
    # https://www.lieben.nu/liebensraum/2020/08/get-tenant-id-using-azure-subscription-id/
    
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://management.azure.com/subscriptions/$($SubscriptionId)`?api-version=2015-01-01" -ErrorAction Stop
    } catch {
        # The error response contains the WWW-Authenticate header with the tenant ID
        $response = $_.Exception.Response
    }
    
    # Extract tenant ID from WWW-Authenticate header
    $authHeader = $response.Headers.GetValues("WWW-Authenticate")[0]
    
    # Use regex to extract the tenant ID
    if ($authHeader -match "login\.windows\.net\/([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})") {
        return $matches[1]
    }
    
    return $null
}
