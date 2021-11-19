using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Write-Host "PowerShell HTTP trigger function processed a request."

$TenantFilter = $request.query.tenantfilter
$SuspectUser = $($request.query.userid)
Write-Host $TenantFilter
Write-Host $SuspectUser
try {
    $startDate = (Get-Date).AddDays(-7)
    $endDate = (Get-Date)
    $upn = "notRequired@required.com"
    $tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $TenantFilter).Authorization -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($TenantFilter)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ErrorAction Continue
    $s = Import-PSSession $session -ea Silentlycontinue -AllowClobber -CommandName "Search-unifiedAuditLog", "Get-AdminAuditLogConfig"
    $7dayslog = if ((Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled -eq $false) {
        "AuditLog is disabled. Cannot perform full analysis"
    }
    else {
        $sessionid = Get-Random -Minimum 10000 -Maximum 99999
        $operations = @(
            'Add OAuth2PermissionGrant.',
            'Consent to application.',
            "New-InboxRule",
            "Set-InboxRule",
            "UpdateInboxRules",
            "Remove-MailboxPermission",
            "Add-MailboxPermission",
            "UpdateCalendarDelegation",
            "AddFolderPermissions",
            "MailboxLogin",
            "Add user.",
            "Change user password.",
            "Reset user password."
        )
        do {
            $logsTenant = Search-unifiedAuditLog -SessionCommand ReturnLargeSet -ResultSize 5000 -StartDate $startDate -EndDate $endDate -sessionid $sessionid -Operations $operations
            Write-Host "Retrieved $($logsTenant.count) logs" -ForegroundColor Yellow
            $logsTenant
        } while ($LogsTenant.count % 5000 -eq 0 -and $LogsTenant.count -ne 0)
    }
    Get-PSSession | Remove-PSSession
    #Get user last logon
    $uri = "https://login.microsoftonline.com/$($TenantFilter)/oauth2/token"
    $body = "resource=https://admin.microsoft.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    Write-Host "getting token"
    $token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
    Write-Host "got token"
    $LastSignIn = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri "https://admin.microsoft.com/admin/api/users/$($SuspectUser)/lastSignInInfo" -Method GET -Headers @{
        Authorization            = "Bearer $($token.access_token)";
        "x-ms-client-request-id" = [guid]::NewGuid().ToString();
        "x-ms-client-session-id" = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }
    #List all users devices
    Write-Host "Last Sign in is: $LastSignIn"
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($SuspectUser)
    $base64IdentityParam = [Convert]::ToBase64String($Bytes)
    Try {
        $Devices = New-GraphGetRequest -uri "https://outlook.office365.com:443/adminapi/beta/$($TenantFilter)/mailbox('$($base64IdentityParam)')/MobileDevice/Exchange.GetMobileDeviceStatistics()/?IsEncoded=True" -Tenantid $tenantfilter -scope ExchangeOnline
    }
    catch {
        $Devices = $null
    }
    $Results = [PSCustomObject]@{
        AddedApps                = @(($7dayslog | Where-Object -Property Operations -In 'Add OAuth2PermissionGrant.', 'Consent to application.').AuditData | ConvertFrom-Json)
        SuspectUserMailboxLogons = @(($7dayslog | Where-Object -Property Operations -In  "MailboxLogin" ).AuditData | ConvertFrom-Json)
        LastSuspectUserLogon     = @($LastSignIn)
        SuspectUserDevices       = @($Devices)
        NewRules                 = @(($7dayslog | Where-Object -Property Operations -In "New-InboxRule", "Set-InboxRule", "UpdateInboxRules").AuditData | ConvertFrom-Json)
        MailboxPermissionChanges = @(($7dayslog | Where-Object -Property Operations -In "Remove-MailboxPermission", "Add-MailboxPermission", "UpdateCalendarDelegation", "AddFolderPermissions" ).AuditData | ConvertFrom-Json)
        NewUsers                 = @(($7dayslog | Where-Object -Property Operations -In "Add user.").AuditData | ConvertFrom-Json)
        ChangedPasswords         = @(($7dayslog | Where-Object -Property Operations -In "Change user password.", "Reset user password.").AuditData | ConvertFrom-Json)
    }
    
    Write-Host $Results
    #Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Assigned $($appFilter) to $assignTo" -Sev "Info"

}
catch {
    #Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to assign app $($appFilter): $($_.Exception.Message)" -Sev "Error"
    $results = [pscustomobject]@{"Results" = "Failed to assign. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = (ConvertTo-Json -Depth 10 -InputObject $Results)
    })
