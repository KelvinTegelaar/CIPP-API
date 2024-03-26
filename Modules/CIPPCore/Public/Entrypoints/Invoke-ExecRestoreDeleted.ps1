using namespace System.Net

Function Invoke-ExecRestoreDeleted {
      <#
    .FUNCTIONALITY
    Entrypoint
    #>
      [CmdletBinding()]
      param($Request, $TriggerMetadata)

      $APIName = $TriggerMetadata.FunctionName
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

      # Interact with query parameters or the body of the request.
      $TenantFilter = $Request.Query.TenantFilter

      try {
            $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$($Request.query.ID)/restore" -tenantid $TenantFilter -type POST -body '{}' -verbose
            $Results = [pscustomobject]@{'Results' = 'Successfully completed request.' }
      } catch {
            $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
      }

      # Associate values to output bindings by calling 'Push-OutputBinding'.
      Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                  StatusCode = [HttpStatusCode]::OK
                  Body       = $Results
            })

}
