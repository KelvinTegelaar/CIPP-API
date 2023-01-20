using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
try {
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$($request.query.guid)'" -tenantid $TenantFilter | ForEach-Object { 
        (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys/$($_.id)?`$select=key" -tenantid $TenantFilter).key
    }


    $StatusCode = [HttpStatusCode]::OK
    $Body = [pscustomobject]@{"Results" = $GraphRequest }

}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $Body = [pscustomobject]@{"Results" = "Failed. $ErrorMessage" }

}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
