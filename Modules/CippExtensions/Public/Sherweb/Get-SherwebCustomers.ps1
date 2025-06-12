function Get-SherwebCustomers {
    $AuthHeader = Get-SherwebAuthentication
    $CustomersList = Invoke-RestMethod -Uri 'https://api.sherweb.com/service-provider/v1/customers' -Method GET -Headers $AuthHeader
    return $CustomersList.items
}
