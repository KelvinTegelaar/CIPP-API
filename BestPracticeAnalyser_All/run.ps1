param($tenant)

# Prepare tokens, connections and variables that will be used multiple times later
$uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
$body = "resource=https://admin.microsoft.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
try {
    $token = Invoke-RestMethod $uri -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction SilentlyContinue -Method post
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Token retrieved for Best Practice Analyser on $($tenant)" -sev 'Info'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Unable to Retrieve token for Best Practice Analyser $($tenant) Error: $($_.exception.message)" -sev 'Error'
}
$TenantName = Get-Tenants | Where-Object -Property defaultDomainName -EQ $tenant
# Build up the result object that will be passed back to the durable function
$Result = [pscustomobject]@{
    Tenant                           = "$($TenantName.displayName)"
    GUID                             = "$($TenantName.customerId)"
    LastRefresh                      = $(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
    SecureDefaultState               = ''
    PrivacyEnabled                   = ''
    UnifiedAuditLog                  = ''
    MessageCopyForSend               = ''
    MessageCopyForSendAsCount        = ''
    MessageCopyForSendOnBehalfCount  = ''
    MessageCopyForSendList           = ''
    ShowBasicAuthSettings            = ''
    EnableModernAuth                 = ''
    AllowBasicAuthActiveSync         = ''
    AllowBasicAuthImap               = ''
    AllowBasicAuthPop                = ''
    AllowBasicAuthWebServices        = ''
    AllowBasicAuthPowershell         = ''
    AllowBasicAuthAutodiscover       = ''
    AllowBasicAuthMapi               = ''
    AllowBasicAuthOfflineAddressBook = ''
    AllowBasicAuthRpc                = ''
    AllowBasicAuthSmtp               = ''
    AdminConsentForApplications      = ''
    DoNotExpirePasswords             = ''
    SelfServicePasswordReset         = ''
    DisabledSharedMailboxLogins      = ''
    DisabledSharedMailboxLoginsCount = ''
    UnusedLicensesCount              = ''
    UnusedLicensesTotal              = ''
    UnusedLicensesResult             = ''
    UnusedLicenseList                = ''
    SecureScoreCurrent               = ''
    SecureScoreMax                   = ''
    SecureScorePercentage            = ''
}

# Starting the Best Practice Analyser
    
# Get the Secure Default State
try {
    $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $tenant)
    $Result.SecureDefaultState = $SecureDefaultsState.IsEnabled

    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Security Defaults State on $($tenant) is $($SecureDefaultsState.IsEnabled)" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Security Defaults State on $($tenant) Error: $($_.exception.message)" -sev 'Error'
}


# Get the Privacy Enabled State
try {
    $Result.PrivacyEnabled = Invoke-RestMethod -ContentType 'application/json;charset=UTF-8' -Uri 'https://admin.microsoft.com/admin/api/reports/config/GetTenantConfiguration' -Method Get -Headers @{
        Authorization            = "Bearer $($token.access_token)";
        'x-ms-client-request-id' = [guid]::NewGuid().ToString();
        'x-ms-client-session-id' = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    } | Select-Object -ExpandProperty Output | ConvertFrom-Json | Select-Object -ExpandProperty PrivacyEnabled
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Privacy Enabled State on $($tenant) is $($Result.PrivacyEnabled)" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Privacy Enabled State on $($tenant) Error: $($_.exception.message)" -sev 'Error'
}

# Get Send and Send Behalf Of
try {
    # Send and Send Behalf Of
    $MailboxBPA = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' | Where-Object { $_.RecipientTypeDetails -In @('UserMailbox', 'SharedMailbox') -and $_.userPrincipalName -notlike 'DiscoverySearchMailbox' }
    $TotalMailboxes = $MailboxBPA | Measure-Object | Select-Object -ExpandProperty Count
    $TotalMessageCopyForSentAsEnabled = $MailboxBPA | Where-Object { $_.MessageCopyForSentAsEnabled -eq $true } | Measure-Object | Select-Object -ExpandProperty Count
    $TotalMessageCopyForSendOnBehalfEnabled = $MailboxBPA | Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $true } | Measure-Object | Select-Object -ExpandProperty Count
    If (($TotalMailboxes -eq $TotalMessageCopyForSentAsEnabled) -and ($TotalMailboxes -eq $TotalMessageCopyForSendOnBehalfEnabled)) {
        $Result.MessageCopyForSend = 'PASS'
        $Result.MessageCopyForSendAsCount = $TotalMessageCopyForSentAsEnabled
        $Result.MessageCopyForSendOnBehalfCount = $TotalMessageCopyForSendOnBehalfEnabled
    }
    else {
        $Result.MessageCopyForSend = 'FAIL'
        $Result.MessageCopyForSendAsCount = $MailboxBPA | Where-Object { $_.MessageCopyForSentAsEnabled -eq $false } | Measure-Object | Select-Object -ExpandProperty Count
        $Result.MessageCopyForSendOnBehalfCount = $MailboxBPA | Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $false } | Measure-Object | Select-Object -ExpandProperty Count
        $Result.MessageCopyForSendList = ($MailboxBPA | Where-Object { ($_.MessageCopyForSendOnBehalfEnabled -eq $false) -or ( $_.MessageCopyForSendOnBehalfEnabled -eq $false) } | Select-Object -ExpandProperty userPrincipalName) -join '<br />'
    }
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Send and Send Behalf Of on $($tenant) is $($Result.MessageCopyForSend)" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Send and Send Behalf Of on $($tenant) Error: $($_.exception.message)" -sev 'Error'
}


# Get Unified Audit Log
try {
    $EXOAdminAuditLogConfig = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AdminAuditLogConfig'
    $Result.UnifiedAuditLog = $EXOAdminAuditLogConfig | Select-Object -ExpandProperty UnifiedAuditLogIngestionEnabled
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Unified Audit Log on $($tenant) is $($Result.UnifiedAuditLog)" -sev 'Debug'
    
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Unified Audit Log on $($tenant). Error: $($_.exception.message)" -sev 'Error'
}

# Get Basic Auth States
try {
    $BasicAuthDisable = Invoke-RestMethod -ContentType 'application/json;charset=UTF-8' -Uri 'https://admin.microsoft.com/admin/api/services/apps/modernAuth' -Method GET -Headers @{
        Authorization            = "Bearer $($token.access_token)";
        'x-ms-client-request-id' = [guid]::NewGuid().ToString();
        'x-ms-client-session-id' = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }
    $Result.ShowBasicAuthSettings = $BasicAuthDisable.ShowBasicAuthSettings
    $Result.EnableModernAuth = $BasicAuthDisable.EnableModernAuth
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
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Basic Auth States on $($tenant) run" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Basic Auth States on $($tenant). Error: $($_.exception.message)" -sev 'Error'
}


# Get OAuth Admin Consenst
try {
    $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant -asApp $true
    $Result.AdminConsentForApplications = if ($GraphRequest.permissionGrantPolicyIdsAssignedToDefaultUserRole -eq 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy') { $true } else { $false }
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "OAuth Admin Consent on $($tenant). Admin Consent for Applications $($Result.AdminConsentForApplications) and password reset is $($Result.SelfServicePasswordReset)" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "OAuth Admin Consent on $($tenant). Error: $($_.exception.message)" -sev 'Error'   
}

# Get Self Service Password Reset State
try {
    $bodypasswordresetpol = "resource=74658136-14ec-4630-ad9b-26e160ff0fc6&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    $tokensspr = Invoke-RestMethod $uri -Body $bodypasswordresetpol -ContentType 'application/x-www-form-urlencoded' -ErrorAction SilentlyContinue -Method post
    $SSPRGraph = Invoke-RestMethod -ContentType 'application/json;charset=UTF-8' -Uri 'https://main.iam.ad.ext.azure.com/api/PasswordReset/PasswordResetPolicies' -Method GET -Headers @{
        Authorization            = "Bearer $($tokensspr.access_token)";
        'x-ms-client-request-id' = [guid]::NewGuid().ToString();
        'x-ms-client-session-id' = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }
    If ($SSPRGraph.enablementType -eq 0) { $Result.SelfServicePasswordReset = 'Off' }
    If ($SSPRGraph.enablementType -eq 1) { $Result.SelfServicePasswordReset = 'Specific Users' }
    If ($SSPRGraph.enablementType -eq 2) { $Result.SelfServicePasswordReset = 'On' }
    If ([string]::IsNullOrEmpty($SSPRGraph.enablementType)) { $Result.SelfServicePasswordReset = 'Unknown' }
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Basic Self Service Password State on $($tenant) is $($Result.SelfServicePasswordReset) run" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Self Service Password Reset on $($tenant). Error: $($_.exception.message)" -sev 'Error' 
}

# Get Passwords set to Never Expire
try {
    $Result.DoNotExpirePasswords = Invoke-RestMethod -ContentType 'application/json; charset=utf-8' -Uri 'https://admin.microsoft.com/admin/api/Settings/security/passwordpolicy' -Method GET -Headers @{Authorization = "Bearer $($token.access_token)"; 'x-ms-client-request-id' = [guid]::NewGuid().ToString(); 'x-ms-client-session-id' = [guid]::NewGuid().ToString(); 'X-Requested-With' = 'XMLHttpRequest'; 'x-ms-correlation-id' = [guid]::NewGuid() } | Select-Object -ExpandProperty NeverExpire
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Passwords never expire setting on $($tenant). $($Result.DoNotExpirePasswords)" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Passwords never expire setting on $($tenant). Error: $($_.exception.message)" -sev 'Error' 
}


# Get Shared Mailbox Stuff
try {
    $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenant)/Mailbox" -Tenantid $tenant -scope ExchangeOnline | Where-Object -propert RecipientTypeDetails -EQ 'SharedMailbox')
    $AllUsersAccountState = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?select=userPrincipalName,accountEnabled' -tenantid $Tenant
    $EnabledUsersWithSharedMailbox = foreach ($SharedMailbox in $SharedMailboxList) {
        # Match the User
        $User = $AllUsersAccountState | Where-Object { $_.userPrincipalName -eq $SharedMailbox.userPrincipalName } | Select-Object -First 1
        if ($User.accountEnabled) {
            $User.userPrincipalName
        }
    }
    
    if (($EnabledUsersWithSharedMailbox | Measure-Object | Select-Object -ExpandProperty Count) -gt 0) { $Result.DisabledSharedMailboxLogins = ($EnabledUsersWithSharedMailbox) -join '<br />' } else { $Result.DisabledSharedMailboxLogins = 'PASS' } 
    $Result.DisabledSharedMailboxLoginsCount = $EnabledUsersWithSharedMailbox | Measure-Object | Select-Object -ExpandProperty Count
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Shared Mailbox Enabled Accounts on $($tenant). $($Result.DisabledSharedMailboxLogins)" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Shared Mailbox Enabled Accounts on $($tenant). Error: $($_.exception.message)" -sev 'Error'  
}

# Get unused Licenses
try {
    $LicenseUsage = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $Tenant
    # Import the licenses conversion table
    Set-Location (Get-Item $PSScriptRoot).Parent.FullName
    $ConvertTable = Import-Csv Conversiontable.csv | Sort-Object -Property 'guid' -Unique
    $Table = Get-CIPPTable -TableName ExcludedLicenses
    $ExcludeList = Get-AzDataTableEntity @Table
    $UnusedLicenses = $LicenseUsage | Where-Object { ($_.prepaidUnits.enabled -ne $_.consumedUnits) -and ($_.SkuID -notin $ExcludeList.GUID) }
    $UnusedLicensesCount = $UnusedLicenses | Measure-Object | Select-Object -ExpandProperty Count
    $UnusedLicensesResult = if ($UnusedLicensesCount -gt 0) { 'FAIL' } else { 'PASS' }
    $Result.UnusedLicenseList = foreach ($License in $UnusedLicenses) {
        $PrettyName = ($ConvertTable | Where-Object { $_.guid -eq $License.skuid }).'Product_Display_Name' | Select-Object -Last 1
        if (!$PrettyName) { $PrettyName = $License.skuPartNumber } 
        [PSCustomObject]@{
            License   = $($PrettyName)
            Purchased = $($License.prepaidUnits.enabled)
            Consumed  = $($License.consumedUnits)
        }
    }
    
    $TempCount = 0
    foreach ($License in $UnusedLicenses) {
        $TempCount = $TempCount + ($($License.prepaidUnits.enabled) - $($License.ConsumedUnits))
    }
    $Result.UnusedLicenseList = @($Result.UnusedLicenseList)
    $Result.UnusedLicensesTotal = $TempCount
    $Result.UnusedLicensesCount = $UnusedLicensesCount
    $Result.UnusedLicensesResult = $UnusedLicensesResult
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Unused Licenses on $($tenant). $($Result.UnusedLicensesCount) total not matching" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Unused Licenses on $($tenant). Error: $($_.exception.message)" -sev 'Error'
}

# Get Secure Score
try {
    $SecureScore = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/security/secureScores?`$top=1" -tenantid $tenant -noPagination $true
    $Result.SecureScoreCurrent = $SecureScore.currentScore
    $Result.SecureScoreMax = $SecureScore.maxScore
    $Result.SecureScorePercentage = [int](($SecureScore.currentScore / $SecureScore.maxScore) * 100)
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Secure Score on $($tenant) is $($Result.SecureScoreCurrent) / $($Result.SecureScoreMax)" -sev 'Debug'
}
catch {
    Write-LogMessage -API 'BestPracticeAnalyser' -tenant $tenant -message "Secure Score Retrieval on $($tenant). Error: $($_.exception.message)" -sev 'Error' 
}

@{
    Results      = ($Result | ConvertTo-Json)
    PartitionKey = "bpa"
    RowKey       = "$($TenantName.customerId)"
}