param($tenant)

try {
    $uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
    $bodypasswordresetpol = "resource=74658136-14ec-4630-ad9b-26e160ff0fc6&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    $tokensspr = Invoke-RestMethod $uri -Body $bodypasswordresetpol -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
    $bodysspr = '{"objectId":"default","enablementType":2,"numberOfAuthenticationMethodsRequired":2,"emailOptionEnabled":true,"mobilePhoneOptionEnabled":true,"officePhoneOptionEnabled":false,"securityQuestionsOptionEnabled":false,"mobileAppNotificationEnabled":true,"mobileAppCodeEnabled":true,"numberOfQuestionsToRegister":5,"numberOfQuestionsToReset":3,"registrationRequiredOnSignIn":true,"registrationReconfirmIntevalInDays":180,"skipRegistrationAllowed":true,"skipRegistrationMaxAllowedDays":7,"customizeHelpdeskLink":false,"customHelpdeskEmailOrUrl":"","notifyUsersOnPasswordReset":true,"notifyOnAdminPasswordReset":true,"passwordResetEnabledGroupIds":[],"passwordResetEnabledGroupName":"","securityQuestions":[],"registrationConditionalAccessPolicies":[],"emailOptionAllowed":true,"mobilePhoneOptionAllowed":true,"officePhoneOptionAllowed":true,"securityQuestionsOptionAllowed":true,"mobileAppNotificationOptionAllowed":true,"mobileAppCodeOptionAllowed":true}'
    $SSPRGraph = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri 'https://main.iam.ad.ext.azure.com/api/PasswordReset/PasswordResetPolicies' -Method PUT -Body $bodysspr -Headers @{
        Authorization            = "Bearer $($tokensspr.access_token)";
        "x-ms-client-request-id" = [guid]::NewGuid().ToString();
        "x-ms-client-session-id" = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }
  Write-LogMessage -API "Standards" -tenant $tenant -message "SSPR enabled" -sev Info
}
catch {
  Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to enable SSPR $($_.exception.message)"
}