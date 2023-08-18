using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
try {
      $TAP = New-CIPPTAP -userid $Request.query.ID -TenantFilter $Request.query.tenantfilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal'
      $Results = [pscustomobject]@{"Results" = "$TAP" }
}
catch {
      $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })