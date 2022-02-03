using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$results = try { 
    $Request.body | ConvertTo-Json | Set-Content ".\Config\Config_Notifications.Json"
    Set-Content '.\Cache_Scheduler\_DefaultNotifications.json' -Value '{ "tenant": "any","Type": "CIPPNotifications" }'
    "succesfully set the configuration"
}
catch {
    "Failed to set configuration"
}


$body = [pscustomobject]@{"Results" = $Results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
