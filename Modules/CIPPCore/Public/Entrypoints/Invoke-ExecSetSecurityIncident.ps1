using namespace System.Net

Function Invoke-ExecSetSecurityIncident {
  <#
    .FUNCTIONALITY
    Entrypoint
    #>
  [CmdletBinding()]
  param($Request, $TriggerMetadata)

  $APIName = $TriggerMetadata.FunctionName
  Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

  $first = ''
  # Interact with query parameters or the body of the request.
  $tenantfilter = $Request.Query.TenantFilter
  $IncidentFilter = $Request.Query.GUID
  $Status = $Request.Query.Status
  $Assigned = $Request.Query.Assigned
  $Classification = $Request.Query.Classification
  $Determination = $Request.Query.Determination
  $Redirected = $Request.Query.Redirected -as [int]
  $BodyBuild
  $AssignBody = '{'

  try {
    # We won't update redirected incidents because the incident it is redirected to should instead be updated
    if ($Redirected -lt 1) {
      # Set received status
      if ($null -ne $Status) {
        $AssignBody += $first + '"status":"' + $Status + '"'
        $BodyBuild += $first + 'Set status for incident to ' + $Status
        $first = ', '
      }

      # Set received classification and determination
      if ($null -ne $Classification) {
        if ($null -eq $Determination) {
          # Maybe some poindexter tries to send a classification without a determination
          throw
        }

        $AssignBody += $first + '"classification":"' + $Classification + '", "determination":"' + $Determination + '"'
        $BodyBuild += $first + 'Set classification & determination for incident to ' + $Classification + ' ' + $Determination
        $first = ', '
      }

      # Set received asignee
      if ($null -ne $Assigned) {
        $AssignBody += $first + '"assignedTo":"' + $Assigned + '"'
        if ($null -eq $Status) {
          $BodyBuild += $first + 'Set assigned for incident to ' + $Assigned
        }
        $first = ', '
      }

      $AssignBody += '}'

      $ResponseBody = [pscustomobject]@{'Results' = $BodyBuild }
      New-Graphpostrequest -uri "https://graph.microsoft.com/beta/security/incidents/$IncidentFilter" -type PATCH -tenantid $TenantFilter -body $Assignbody -asApp $true
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Update incident $IncidentFilter with values $Assignbody" -Sev 'Info'
    } else {
      $ResponseBody = [pscustomobject]@{'Results' = 'Cannot update redirected incident' }
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Refuse to pdate incident $IncidentFilter with values $Assignbody because it is redirected to another incident" -Sev 'Info'
    }

    $body = $ResponseBody
  } catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to update alert $($AlertFilter): $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed to update incident: $($_.Exception.Message)" }
  }

  # Associate values to output bindings by calling 'Push-OutputBinding'.
  Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
      StatusCode = [HttpStatusCode]::OK
      Body       = $body
    })

}
