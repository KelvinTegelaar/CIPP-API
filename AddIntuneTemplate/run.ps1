using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"



try {        
    if (!$Request.body.displayname) { throw "You must enter a displayname" }
    if (!$Request.body.rawjson) { throw "You must fill in the RAW json" }
    if ($null -eq ($Request.body.Rawjson | ConvertFrom-Json)) { throw "the JSON is invalid" }
    $GUID = New-Guid

    $object = [PSCustomObject]@{
        Displayname = $request.body.displayname
        Description = $request.body.description
        RAWJson     = $request.body.RawJSON
        Type        = $request.body.TemplateType
        GUID        = $GUID
    } | ConvertTo-Json
    New-Item Config -ItemType Directory -ErrorAction SilentlyContinue
    Set-Content "Config\$($GUID).IntuneTemplate.json" -Value $Object -Force
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Created intune policy template named $($Request.body.displayname) with GUID $GUID" -Sev "Debug"

    $body = [pscustomobject]@{"Results" = "Successfully added template" }
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal'  -API $APINAME -message "Intune Template Deployment failed: $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Intune Template Deployment failed: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
