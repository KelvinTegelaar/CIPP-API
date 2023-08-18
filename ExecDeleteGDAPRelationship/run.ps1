using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
$GDAPID = $request.query.GDAPId
try {
      $DELETE = New-GraphPostRequest -NoAuthCheck $True -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web/v1/delegatedAdminRelationships/$($GDAPID)/requests" -type POST -body '{"action":"terminate"}' -tenantid $env:TenantID -scope 'https://api.partnercustomeradministration.microsoft.com/.default'
      $Results = [pscustomobject]@{"Results" = "Success. GDAP relationship for $($GDAPID) been revoked" }
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Success. GDAP relationship for $($GDAPID) been revoked" -Sev "Info"

}
catch {
      $Results = [pscustomobject]@{"Results" = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })