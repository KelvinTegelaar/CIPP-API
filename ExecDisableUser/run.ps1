using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$Body = if ($Request.Query.Enable) { '{"accountEnabled":"true"}' } else { '{"accountEnabled":"false"}' }
try {
      $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.query.ID)" -tenantid $TenantFilter -type PATCH -body $Body  -verbose
      $Results = [pscustomobject]@{"Results" = "Successfully changed state for $($Request.query.ID)" }
}
catch {
      $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })