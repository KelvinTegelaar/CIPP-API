# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

$Refreshtoken = (Get-GraphToken -ReturnRefresh $true).Refresh_token

if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    $AzSession = Connect-AzAccount -Identity
}

$KV = $ENV:WEBSITE_DEPLOYMENT_ID

if ($Refreshtoken) { 
    Set-AzKeyVaultSecret -VaultName $kv -Name 'RefreshToken' -SecretValue (ConvertTo-SecureString -String $Refreshtoken -AsPlainText -Force)
}
else { 
    Write-LogMessage -message "Could not update refresh token. Will try again in 7 days." -sev "CRITICAL" 
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

