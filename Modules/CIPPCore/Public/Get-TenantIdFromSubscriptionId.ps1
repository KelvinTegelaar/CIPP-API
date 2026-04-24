function Get-TenantIdFromSubscriptionId {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    # Full credit goes to Jos Lieben
    # https://www.lieben.nu/liebensraum/2020/08/get-tenant-id-using-azure-subscription-id/

    # An unauthenticated request to ARM returns 401 with a WWW-Authenticate
    # header that embeds the tenant ID. SkipHttpErrorCheck keeps the response
    # flowing so we can read the header off the result.
    $null = Invoke-CIPPRestMethod -Uri "https://management.azure.com/subscriptions/$($SubscriptionId)`?api-version=2015-01-01" -Method Get -SkipHttpErrorCheck -ResponseHeadersVariable 'AuthResponseHeaders' -ErrorAction SilentlyContinue

    $authHeaderValue = $AuthResponseHeaders['WWW-Authenticate']
    if ($authHeaderValue -is [array]) { $authHeaderValue = $authHeaderValue[0] }

    # Use regex to extract the tenant ID
    if ($authHeaderValue -match 'login\.windows\.net\/([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') {
        return $matches[1]
    }

    return $null
}
