param($tenant)

try {
    $upn = "notRequired@required.com"
    $tokenvalue = convertto-securestring (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $tenant).Authorization -asplaintext -force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($tenant)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ErrorAction Continue
    Import-PSSession $session -ea Silentlycontinue -allowclobber -CommandName "Set-AdminAuditLogConfig", "Get-OrganizationConfig", "Enable-OrganizationCustomization"
    Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true 
    get-pssession | Remove-PSSession
    Log-request "Standards API: $($Tenant) Unified Audit Log Enabled." -sev Info

}
catch {
    Log-request "Standards API: $($tenant) Failed to apply Unified Audit Log. Error: $($_.exception.message)" -sev Error
}