using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
$tenantfilter = $Request.Query.TenantFilter
$IncidentFilter = $Request.Query.GUID
$Status = $Request.Query.Status
$Assigned = $Request.Query.Assigned
$Redirected = $Request.Query.Redirected -as [int]
$AssignBody = '{"status":"' + $Status + '","assignedTo":"'+ $Assigned +'"}'
$ResponseBody = [pscustomobject]@{"Results" = "Set status for incident to $Status" }

if(!$Status) {
    $Redirected = 0
    $AssignBody = '{"assignedTo":"'+ $Assigned +'"}'
    $ResponseBody = [pscustomobject]@{"Results" = "Assigned incident to $Assigned" }
}

if($Redirected -le 0 -or !$Redirected)
{

  try {       
    $GraphRequest = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/security/incidents/$IncidentFilter" -type PATCH -tenantid $TenantFilter -body $Assignbody -asApp $true
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Set incident $IncidentFilter to status $Status" -Sev "Info"
    $body = $ResponseBody

  }
  catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to update incident $($IncidentFilter): $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to change status: $($_.Exception.Message)" }
  }
}
else
{
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Rejected status update of redirected incident $($IncidentFilter): $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Rejected status update of redirected incident" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
