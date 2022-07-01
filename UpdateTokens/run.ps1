# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

$Refreshtoken = (Get-GraphToken -ReturnRefresh $true).Refresh_token
$ExchangeRefreshtoken = (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -refreshtoken $ENV:ExchangeRefreshtoken -ReturnRefresh $true).Refresh_token

if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    $AzSession = Connect-AzAccount -Identity
}

$KV = $ENV:WEBSITE_DEPLOYMENT_ID

if ($Refreshtoken) { 
    Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Refreshtoken -AsPlainText -Force)
}
else { log-request -message "Could not update refresh token. Will try again in 7 days." -sev "CRITICAL" }
if ($ExchangeRefreshtoken -and $KV) {
    Set-AzKeyVaultSecret -VaultName $kv -Name 'ExchangeRefreshToken' -SecretValue (ConvertTo-SecureString -String $ExchangeRefreshtoken -AsPlainText -Force)
    log-request -message "System API: Updated Exchange Refresh token." -sev "info" -API "TokensUpdater"
}
else {
    log-request -message "Could not update Exchange refresh token. Will try again in 7 days." -sev "CRITICAL" -API "TokensUpdater"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

