using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$Body = "{}"
try {
      $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($Request.query.ID)/authentication/temporaryAccessPassMethods" -tenantid $TenantFilter -type POST -body $Body  -verbose
      $Results = [pscustomobject]@{"Results" = "The TAP for this user is $($GraphRequest.temporaryAccessPass) - This TAP is usable for the next $($GraphRequest.LifetimeInMinutes) minutes" }
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Created temporary access pass for user $($Request.Query.id)" -Sev "Info"

}
catch {
      $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })