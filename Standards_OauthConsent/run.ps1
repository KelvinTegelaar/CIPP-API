param($tenant)

try {
    $uri = "https://login.microsoftonline.com/$($tenant)/oauth2/token"
    $body = "resource=74658136-14ec-4630-ad9b-26e160ff0fc6&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    $token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
    $oAuth = Invoke-RestMethod -ContentType "application/json; charset=utf-8"  -Body '{"usersCanRegisterApps":false}' -Method PUT -Uri 'https://main.iam.ad.ext.azure.com/api/Directories/PropertiesV2' -Headers @{Authorization = "Bearer $($token.access_token)"; "x-ms-client-request-id" = [guid]::NewGuid().ToString(); "x-ms-client-session-id" = [guid]::NewGuid().ToString() }
    Log-request -API "Standards" -tenant $tenant -message  "Application Consent Mode has been enabled." -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Failed to apply Application Consent Mode Error: $($_.exception.message)" -sev Error
}