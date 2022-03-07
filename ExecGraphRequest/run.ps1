using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$TenantFilter = $Request.Query.TenantFilter
try {
        if ($TenantFilter -ne "AllTenants") {
                $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$($Request.Query.Endpoint)" -tenantid $TenantFilter
        }
        else {
                $GraphRequest = Get-tenants | ForEach-Object { New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$($Request.Query.Endpoint)" -tenantid $_ }

        }
        $StatusCode = [HttpStatusCode]::OK
}
catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @($GraphRequest)
        })
