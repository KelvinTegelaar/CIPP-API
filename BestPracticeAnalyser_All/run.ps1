param($tenant)

# Prepare connections and variables that will be used multiple times later
$uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
$body = "resource=https://admin.microsoft.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
$token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
$upn = "notRequired@required.com"

$Result = [PSCustomObject]@{
    Tenant = $tenant
    SecureDefaultState = ""
    PrivacyEnabled = ""
    UnifiedAuditLog = ""
    MessageCopyForSend = ""
    ShowBasicAuthSettings = ""
    EnableModernAuth = ""
    SecureDefaults = ""
    DisableModernAuth = ""
    AllowBasicAuthActiveSync = ""
    AllowBasicAuthImap = ""
    AllowBasicAuthPop = ""
    AllowBasicAuthWebServices = ""
    AllowBasicAuthPowershell = ""
    AllowBasicAuthAutodiscover = ""
    AllowBasicAuthMapi = ""
    AllowBasicAuthOfflineAddressBook = ""
    AllowBasicAuthRpc = ""
    AllowBasicAuthSmtp = ""
    SharedMailboxUserEnabled = ""
}

# Get the Secure Default State
try {
    $SecureDefaultsState = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy" -tenantid $tenant)
    $Result.SecureDefaultState = $SecureDefaultsState.IsEnabled

    Log-request -API "Standards" -tenant $tenant -message "Best Practice Analyser API: Security Defaults State is $($SecureDefaultsState.IsEnabled)" -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Best Practice Analyser API Error: $($_.exception.message)"
}

# Get the Privacy Enabled State
try {
    $Result.PrivacyEnabled = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri 'https://admin.microsoft.com/admin/api/reports/config/GetTenantConfiguration' -Method Get -Headers @{
        Authorization            = "Bearer $($token.access_token)";
        "x-ms-client-request-id" = [guid]::NewGuid().ToString();
        "x-ms-client-session-id" = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    } | Select -ExpandProperty Output | ConvertFrom-Json | Select -ExpandProperty PrivacyEnabled
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Best Practice Analyser Privacy Enabled API Error: $($_.exception.message)"
}

# Get Message Send and Send Behalf Of and Unified Audit Log
try {
    $tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $($Tenant)).Authorization -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($Tenant)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ErrorAction Continue
    Import-PSSession $session -ea Silentlycontinue -AllowClobber -CommandName "Get-Mailbox", "Set-mailbox", "Get-AdminAuditLogConfig", "Get-OrganizationConfig", "Enable-OrganizationCustomization" | Out-Null

    # Send and Send Behalf Of
    $MailboxBPA = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox, SharedMailbox
    $TotalMailboxes = $MailboxBPA | Measure-Object | Select-Object -ExpandProperty Count
    $TotalMessageCopyForSentAsEnabled = $MailboxBPA | Where-Object {$_.MessageCopyForSentAsEnabled -eq $true} | Measure-Object | Select-Object -ExpandProperty Count
    $TotalMessageCopyForSendOnBehalfEnabled = $MailboxBPA | Where-Object {$_.MessageCopyForSendOnBehalfEnabled -eq $true} | Measure-Object | Select-Object -ExpandProperty Count
    If (($TotalMailboxes -eq $TotalMessageCopyForSentAsEnabled) -and ($TotalMailboxes -eq $TotalMessageCopyForSendOnBehalfEnabled)){
        $Result.MessageCopyForSend = "PASS"
    }
    else {
        $Result.MessageCopyForSend = "$TotalMailboxes mailboxes / $TotalMessageCopyForSentAsEnabled SentAs / $TotalMessageCopyForSendOnBehalfEnabled SendBehalf"
    }

    # Unified Audit Log
    $Result.UnifiedAuditLog = Get-AdminAuditLogConfig | Select-Object -ExpandProperty UnifiedAuditLogIngestionEnabled


    # Cleanup
    Get-PSSession | Remove-PSSession
}
catch {
    Log-request  -API "Standards" -tenant $tenant -message "Failed to apply Delegate Sent Items Style. Error: $($_.exception.message)" -sev Error
}

# Get Basic Auth Stuff
try {
    $BasicAuthDisable = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri 'https://admin.microsoft.com/admin/api/services/apps/modernAuth' -Method GET -Headers @{
        Authorization            = "Bearer $($token.access_token)";
        "x-ms-client-request-id" = [guid]::NewGuid().ToString();
        "x-ms-client-session-id" = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }

    $Result.ShowBasicAuthSettings = $BasicAuthDisable.ShowBasicAuthSettings
    $Result.EnableModernAuth = $BasicAuthDisable.EnableModernAuth
    $Result.SecureDefaults = $BasicAuthDisable.SecureDefaults
    $Result.DisableModernAuth = $BasicAuthDisable.DisableModernAuth
    $Result.AllowBasicAuthActiveSync = $BasicAuthDisable.AllowBasicAuthActiveSync
    $Result.AllowBasicAuthImap = $BasicAuthDisable.AllowBasicAuthImap
    $Result.AllowBasicAuthPop = $BasicAuthDisable.AllowBasicAuthPop
    $Result.AllowBasicAuthWebServices = $BasicAuthDisable.AllowBasicAuthWebServices
    $Result.AllowBasicAuthPowershell = $BasicAuthDisable.AllowBasicAuthPowershell
    $Result.AllowBasicAuthAutodiscover = $BasicAuthDisable.AllowBasicAuthAutodiscover
    $Result.AllowBasicAuthMapi = $BasicAuthDisable.AllowBasicAuthMapi
    $Result.AllowBasicAuthOfflineAddressBook = $BasicAuthDisable.AllowBasicAuthOfflineAddressBook
    $Result.AllowBasicAuthRpc = $BasicAuthDisable.AllowBasicAuthRpc
    $Result.AllowBasicAuthSmtp = $BasicAuthDisable.AllowBasicAuthSmtp
}
catch {
    #Do nothing
}

# Get Shared Mailbox Stuff
try {
    $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenant)/Mailbox" -Tenantid $tenant -scope ExchangeOnline | Where-Object -propert RecipientTypeDetails -EQ "SharedMailbox")
}
catch {
}

$selectlist = "userPrincipalName,accountEnabled"
$EnabledUsers = foreach ($user in $SharedMailboxList) {
    New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($User.ObjectKey)?select=$selectlist" -tenantid $Tenant | ? {$_.accountEnabled -eq $true}
}

if (($EnabledUsers | Measure-Object | Select-Object -ExpandProperty Count) -gt 0) {$Result.SharedMailboxUserEnabled = ($EnabledUsers.userPrincipalName) -join ","} else {$Result.SharedMailboxUserEnabled = "PASS"}



$Result