param($tenant)

try {
    $uri = "https://login.microsoftonline.com/$($tenant)/oauth2/token"
    $body = "resource=https://admin.microsoft.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    $token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -method post
    $PasswordExpire = Invoke-RestMethod -contenttype "application/json; charset=utf-8" -uri 'https://admin.microsoft.com/admin/api/Settings/security/passwordpolicy' -method POST -body '{"ValidityPeriod":900,"NotificationDays":140,"NeverExpire":true}'   -Headers @{Authorization = "Bearer $($token.access_token)"; "x-ms-client-request-id" = [guid]::NewGuid().ToString(); "x-ms-client-session-id" = [guid]::NewGuid().ToString(); 'X-Requested-With' = 'XMLHttpRequest'; 'x-ms-correlation-id' = [guid]::NewGuid() }
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Disabled Password Expiration" -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to disable Password Expiration. Error: $($_.exception.message)" -sev Error
}