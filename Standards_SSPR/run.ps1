param($tenant)

try {
    $uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
    $body = "resource=https://admin.microsoft.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    $token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -method post
    $AnonReports = Invoke-RestMethod -contenttype "application/json;charset=UTF-8" -uri 'https://admin.microsoft.com/admin/api/reports/config/SetTenantConfiguration' -body '{"PrivacyEnabled":false,"PowerBiEnabled":true}' -method POST -Headers @{
        Authorization            = "Bearer $($token.access_token)";
        "x-ms-client-request-id" = [guid]::NewGuid().ToString();
        "x-ms-client-session-id" = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }
    "Standards API succesfully changed anonymous reports"
}
catch {
    "Standards API: Could not connect to disable anonymous reports. Error: $($exception.message)"
}