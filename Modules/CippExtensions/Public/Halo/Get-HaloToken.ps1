function Get-HaloToken {
    [CmdletBinding()]
    param (
        $Configuration
    )
    if (![string]::IsNullOrEmpty($Configuration.ClientID)) {
        $Secret = Get-ExtensionAPIKey -Extension 'HaloPSA'

        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $Configuration.ClientID
            client_secret = $Secret
            scope         = 'all'
        }
        if ($Configuration.Tenant -ne 'None') { $Tenant = "?tenant=$($Configuration.Tenant)" }
        $UserAgent = Get-CippUserAgent
        $token = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Configuration.AuthURL)/token$Tenant" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $token
    } else {
        throw 'No Halo configuration'
    }
}
