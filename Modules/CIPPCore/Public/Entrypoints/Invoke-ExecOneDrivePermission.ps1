using namespace System.Net

Function Invoke-ExecOneDrivePermission {
      <#
    .FUNCTIONALITY
    Entrypoint
    #>
      [CmdletBinding()]
      param($Request, $TriggerMetadata)

      $APIName = $TriggerMetadata.FunctionName
      $tenantFilter = $Request.Body.TenantFilter
      try {
            $State = Set-CIPPOnedriveAccess -tenantFilter $tenantFilter -userid $request.body.UPN -OnedriveAccessUser $request.body.input -ExecutingUser $ExecutingUser -APIName $APIName -RemovePermission $request.body.RemovePermission
            $Results = [pscustomobject]@{'Results' = "$State" }
      } catch {
            $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
      }

      # Associate values to output bindings by calling 'Push-OutputBinding'.
      Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                  StatusCode = [HttpStatusCode]::OK
                  Body       = $Results
            })

}
