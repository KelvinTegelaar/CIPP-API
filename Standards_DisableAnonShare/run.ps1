param($tenant)

try {
    #$uri = "https://login.microsoftonline.com/$($Tenant)/oauth2/token"
    #$SplitDomain = $tenant -split "." | Select-Object -First 1
    #$body = "resource=https://$($SplitDomain)-admin.sharepoint.com&grant_type=refresh_token&refresh_token=$($ENV:ExchangeRefreshToken)"
    #$token = Invoke-RestMethod $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction SilentlyContinue -Method post
    #$AnonSharingDisable = Invoke-RestMethod -ContentType "application/json;odata.metadata=verbose" -Uri "https://$($SplitDomain)-admin.sharepoint.com/_api/SPOInternalUseOnly.Tenant" -Body '{"SharingCapability":1,"ODBSharingCapability":1}' -Method PATCH -Headers @{
    #    Authorization            = "Bearer $($token.access_token)";
    #    "x-ms-client-request-id" = [guid]::NewGuid().ToString();
    #    "x-ms-client-session-id" = [guid]::NewGuid().ToString()
    #    'x-ms-correlation-id'    = [guid]::NewGuid()
    #    'X-Requested-With'       = 'XMLHttpRequest' 
    #}
    Log-request "Standards API: $($Tenant) Anonymous Sharing is not disabled. This is a preview setting." -sev Info
}
catch {
    Log-request "Standards API: $($Tenant) Failed to disable anonymous Sharing. Error: $($_.exception.message)"
}