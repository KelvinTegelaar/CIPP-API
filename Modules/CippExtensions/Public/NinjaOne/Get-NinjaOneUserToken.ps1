function Get-NinjaOneUserToken {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Mints a user-context NinjaOne access token from the refresh token stored by the ticketing Connect flow.
    .DESCRIPTION
        Ticketing writes are refused for the client-credentials token Get-NinjaOneToken returns, so
        they run as the technician who connected. Returns $null when nobody has connected yet.
    #>
    [CmdletBinding()]
    param (
        $Configuration
    )

    $RefreshToken = try { Get-ExtensionAPIKey -Extension 'NinjaOneRefreshToken' } catch { $null }
    if ([string]::IsNullOrWhiteSpace($RefreshToken)) { return $null }

    $Body = @{
        grant_type    = 'refresh_token'
        refresh_token = $RefreshToken
        client_id     = $Configuration.ClientID
        client_secret = (Get-ExtensionAPIKey -Extension 'NinjaOne')
    }
    $Instance = $Configuration.Instance -replace '/ws', '' -replace 'https://', ''
    $Token = Invoke-RestMethod -Uri "https://$Instance/ws/oauth/token" -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded'

    # NinjaOne rotates the refresh token; losing the new one means reconnecting.
    if ($Token.refresh_token -and $Token.refresh_token -ne $RefreshToken) {
        $null = Set-ExtensionAPIKey -Extension 'NinjaOneRefreshToken' -APIKey $Token.refresh_token
    }
    return $Token
}
