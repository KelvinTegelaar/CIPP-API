using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
try {
      ([System.Convert]::ToBoolean($Request.Query.Enable))
      $State = Set-CIPPSignInState -userid $Request.query.ID -TenantFilter $Request.Query.TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -AccountEnabled ([System.Convert]::ToBoolean($Request.Query.Enable))
      $Results = [pscustomobject]@{"Results" = "$State" }
}
catch {
      $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })