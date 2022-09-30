using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$Groups = $Request.body.gdapRoles
$Tenants = $Request.body.selectedTenants
$Results = [System.Collections.ArrayList]@()

foreach ($Tenant in $Tenants) {
      $obj = [PSCustomObject]@{
            tenant    = $Tenant
            gdapRoles = $Groups
      }
      Push-OutputBinding -Name Msg -Value $obj
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Started GDAP Migration for $($tenant.displayName)" -Sev "Debug"
      $results.add("Started GDAP Migration for $($tenant.displayName)") | Out-Null
}
$body = @{Results = @($Results) }
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
      })