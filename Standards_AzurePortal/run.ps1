param($tenant)

try {
    $uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
    $bodypasswordresetpol = "resource=74658136-14ec-4630-ad9b-26e160ff0fc6&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    $tokensspr = Invoke-RestMethod $uri -Body $bodypasswordresetpol -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
    $bodysspr = '{"restrictNonAdminUsers":true}'
    $SSPRGraph = Invoke-RestMethod -ContentType "application/json;charset=UTF-8" -Uri 'https://main.iam.ad.ext.azure.com/api/Directories/PropertiesV2' -Method PUT -Body $bodysspr -Headers @{
        Authorization            = "Bearer $($tokensspr.access_token)";
        "x-ms-client-request-id" = [guid]::NewGuid().ToString();
        "x-ms-client-session-id" = [guid]::NewGuid().ToString()
        'x-ms-correlation-id'    = [guid]::NewGuid()
        'X-Requested-With'       = 'XMLHttpRequest' 
    }
  Write-LogMessage -API "Standards" -tenant $tenant -message "Azure Portal disabled for standard users" -sev Info
}
catch {
  Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to disable Azure Portal for standard users$($_.exception.message)"
}