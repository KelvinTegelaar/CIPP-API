using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$TenantFilter = (get-tenants -IncludeAll -IncludeErrors | Where-Object -Property customerId -EQ $Request.query.Tenantfilter).defaultDomainName
Write-Host "Our Tenantfilter is $TenantFilter"
$GraphRequest = try {
    Set-CIPPCPVConsent -Tenantfilter $TenantFilter
    Add-CIPPApplicationPermission -RequiredResourceAccess "CippDefaults" -ApplicationId $ENV:ApplicationID -tenantfilter $TenantFilter
    Add-CIPPDelegatedPermission -RequiredResourceAccess "CippDefaults" -ApplicationId $ENV:ApplicationID -tenantfilter $TenantFilter
}
catch {
    "Failed to update permissions for $($TenantFilter): $($_.Exception.Message)" 
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{Results = $GraphRequest }
    })
