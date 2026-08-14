function Get-PwPushAccount {
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $ParsedConfig = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ErrorAction SilentlyContinue
    $Configuration = $ParsedConfig.PWPush
    if ($Configuration.Enabled -eq $true -and $Configuration.UseBearerAuth -eq $true) {
        # The accounts endpoint only works on the hosted service with a Pro/Premium bearer token.
        # Anything else fails or returns nothing - surface that as a placeholder row instead of
        # letting the error escape (500) or returning null, which the frontend cannot render.
        try {
            Set-PwPushConfig -Configuration $Configuration -FullConfiguration $ParsedConfig
            $Accounts = @(Get-PushAccount -ErrorAction Stop | Where-Object { $null -ne $_ })
        } catch {
            Write-Information "Failed to retrieve PWPush accounts: $($_.Exception.Message)"
            $Accounts = @()
        }
        if ($Accounts.Count -eq 0) {
            return @(@{
                    name = 'Could not retrieve accounts. Check that your API key is a valid bearer token for a Pro/Premium subscription on the hosted service, or disable Bearer Authentication.';
                    id   = ''
                })
        }
        return $Accounts
    } else {
        return @(@{
                name = 'PWPush Pro is not enabled or configured. Make sure to save the configuration first.';
                id   = ''
            })
    }
}
