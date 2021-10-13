param($tenant)

try {
    $upn = "notRequired@required.com"
    $tokenvalue = convertto-securestring (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $($Tenant)).Authorization -asplaintext -force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($Tenant)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ErrorAction Continue
    Import-PSSession $session -ea Silentlycontinue -allowclobber -CommandName "Get-Mailbox", "Set-mailbox"
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox,SharedMailbox | set-mailbox -erroraction SilentlyContinue -MessageCopyForSentAsEnabled $true -MessageCopyForSendOnBehalfEnabled $true 
    get-pssession | Remove-PSSession
    Log-request "Standards API: $($Tenant) Delegate Sent Items Style enabled." -sev Info
}
catch {
    Log-request "Standards API: $($tenant) Failed to apply Delegate Sent Items Style. Error: $($_.exception.message)" -sev Error
}