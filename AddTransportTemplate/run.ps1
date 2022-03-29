using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


try {        
    $GUID = New-Guid

    $object = [PSCustomObject]@{}
    $request.body.PowerShellCommand | ConvertFrom-Csv -Delimiter " " -Header "name", "value" | ForEach-Object {
        $object | Add-Member -NotePropertyName ($_.name -replace '-', '') -NotePropertyValue $_.value
    }


    New-Item Config -ItemType Directory -ErrorAction SilentlyContinue
    Set-Content "Config\$($GUID).TransportRuleTemplate.json" -Value ($Object | ConvertTo-Json -Depth 10) -Force
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Created Transport Rule Template $($Request.body.displayname) with GUID $GUID" -Sev "Debug"

    $body = [pscustomobject]@{"Results" = "Successfully added template" }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'  -API $APINAME -message "Failed to create Transport Rule Template: $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Intune Template Deployment failed: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
