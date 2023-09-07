using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
if ("AllTenants" -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }

$results = foreach ($Tenant in $tenants) {
    try {
        $CAPolicy = New-CIPPCAPolicy -TenantFilter $tenant -state $request.body.NewState -RawJSON $Request.body.RawJSON -APIName $APIName -ExecutingUser $request.headers.'x-ms-client-principal'
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added Conditional Access Policy $($Displayname)" -Sev "Error"
        "Successfully added Conditional Access Policy for $($Tenant)"
    }
    catch {
        "Failed to add policy for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Failed adding Conditional Access Policy $($Displayname). Error: $($_.Exception.Message)" -Sev "Error"
        continue
    }

}

$body = [pscustomobject]@{"Results" = @($results) }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
