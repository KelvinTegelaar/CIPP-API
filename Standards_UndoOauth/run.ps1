param($tenant)

try {
    $uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
    $body = "resource=https://admin.microsoft.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    $token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
    $oAuth = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri 'https://admin.microsoft.com/admin/api/settings/apps/IntegratedApps' -Body '{"Enabled":true}' -Method POST -Headers @{
        Authorization            = "Bearer $($token.access_token)";
        "x-ms-client-request-id" = [guid]::NewGuid().ToString();
        "x-ms-client-session-id" = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }
    Log-request -API "Standards" -tenant $tenant -message  "Application Consent Mode has been disabled." -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Failed to set Application Consent Mode to disabled Error: $($_.exception.message)" -sev Error
}