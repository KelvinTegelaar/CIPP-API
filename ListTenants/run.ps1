using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName

Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


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

$tenantfilter = $Request.Query.TenantFilter

try {
    if ($null -eq $TenantFilter -or $TenantFilter -eq "null") {
        $Body = Get-Tenants
    }
    else {
        $body = Get-Tenants | Where-Object -Property DefaultdomainName -EQ $Tenantfilter
    }
    Log-Request -user $request.headers.'x-ms-client-principal' -tenant $Tenantfilter -API $APINAME  -message "Listed Tenant Details" -Sev "Info"
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -tenant $Tenantfilter -API $APINAME -message "List Tenant failed. The error is: $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to retrieve tenants: $($_.Exception.Message)" }
}



Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Body)
    })
    
