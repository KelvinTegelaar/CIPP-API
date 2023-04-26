using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$device = $($request.query.guid)
try {
    $GraphRequest = (New-GraphGetRequest -noauthcheck $true -uri "https://graph.microsoft.com/beta/deviceLocalCredentials/$($device)?`$select=credentials" -tenantid $TenantFilter).credentials | Select-Object -First 1 | ForEach-Object {
        $PlainText = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_.passwordBase64))
        $date = $_.BackupDateTime
        "The password for $($_.AccountName) is $($PlainText) generated at $($date)"
        
    }
    $Body = [pscustomobject]@{"Results" = $GraphRequest }

}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $Body = [pscustomobject]@{"Results" = "Failed. $ErrorMessage" }

}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
