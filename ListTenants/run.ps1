using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# We create the excluded tenants file. This is not set to force so will not overwrite
New-Item -ErrorAction SilentlyContinue -ItemType File -Path "ExcludedTenants"

# Set cache locations
$cachefile = 'tenants.cache.json'

# Clear Cache
if ($request.Query.ClearCache -eq "true") {
    Remove-CIPPCache
    $GraphRequest = [pscustomobject]@{"Results" = "Successfully completed request." }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $GraphRequest
        })
    exit
}

$Body = Get-Tenants


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
    
