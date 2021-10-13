using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
if ($TenantFilter -eq $null -or $TenantFilter -eq "null") {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/domains" | select-object id,isdefault,isinitial | sort-object isdefault
}
else {
      $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/domains" -tenantid $TenantFilter | select-object id,isdefault,isinitial | sort-object isdefault
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $GraphRequest
    })