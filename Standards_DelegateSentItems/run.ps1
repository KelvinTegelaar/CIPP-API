param($tenant)

try {
    $upn = "notRequired@required.com"
    $tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $($Tenant)).Authorization -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($Tenant)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ErrorAction Continue
    Import-PSSession $session -ea Silentlycontinue -AllowClobber -CommandName "Get-Mailbox", "Set-mailbox"
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox, SharedMailbox | Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $false -or $_.MessageCopyForSentAsEnabled -eq $false } | set-mailbox -erroraction SilentlyContinue -MessageCopyForSentAsEnabled $true -MessageCopyForSendOnBehalfEnabled $true 
    Get-PSSession | Remove-PSSession
    Log-request  -API "Standards" -tenant $tenant -message "Delegate Sent Items Style enabled." -sev Info
}
catch {
    Log-request  -API "Standards" -tenant $tenant -message "Failed to apply Delegate Sent Items Style. Error: $($_.exception.message)" -sev Error
}