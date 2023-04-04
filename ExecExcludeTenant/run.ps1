using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$user = $request.headers.'x-ms-client-principal'
$username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
$date = (Get-Date).tostring('yyyy-MM-dd')
$TenantsTable = Get-CippTable -tablename Tenants

if ($Request.Query.List) {
    $ExcludedFilter = "PartitionKey eq 'Tenants' and Excluded eq true" 
    $ExcludedTenants = Get-AzDataTableEntity @TenantsTable -Filter $ExcludedFilter 
    Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message 'got excluded tenants list' -Sev 'Info'
    $body = @($ExcludedTenants)
}
elseif ($Request.query.ListAll) {
    $ExcludedTenants = Get-AzDataTableEntity @TenantsTable -filter "PartitionKey eq 'Tenants'" 
    Write-LogMessage -API $APINAME -user $request.headers.'x-ms-client-principal' -message 'got excluded tenants list' -Sev 'Info'
    $body = @($ExcludedTenants)
}
try {
    # Interact with query parameters or the body of the request.
    $name = $Request.Query.TenantFilter
    if ($Request.Query.AddExclusion) {
        $Tenants = Get-Tenants -IncludeAll | Where-Object { $Request.body.value -contains $_.customerId }
       
        $Excluded = foreach ($Tenant in $Tenants) {
            $Tenant.Excluded = $true
            $Tenant.ExcludeUser = $username
            $Tenant.ExcludeDate = $date
            $Tenant
        }
        Write-Host ($Excluded | ConvertTo-Json)
        Update-AzDataTableEntity @TenantsTable -Entity ([pscustomobject]$Excluded)
        #Remove-CIPPCache
        Write-LogMessage -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal' -message "Added exclusion for customer(s): $($Excluded.defaultDomainName -join ',')" -Sev 'Info' 
        $body = [pscustomobject]@{'Results' = "Success. Added exclusions for customer(s): $($Excluded.defaultDomainName -join ',')" }
    }

    if ($Request.Query.RemoveExclusion) {
        $Filter = "PartitionKey eq 'Tenants' and defaultDomainName eq '{0}'" -f $name
        $Tenant = Get-AzDataTableEntity @TenantsTable -Filter $Filter 
        $Tenant.Excluded = $false
        $Tenant.ExcludeUser = ''
        $Tenant.ExcludeDate = ''
        Update-AzDataTableEntity @TenantsTable -Entity $Tenant       
        #Remove-CIPPCache
        Write-LogMessage -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal' -message "Removed exclusion for customer $($name)" -Sev 'Info'
        $body = [pscustomobject]@{'Results' = "Success. We've removed $name from the excluded tenants." }
    }
}
catch {
    Write-LogMessage -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal' -message "Exclusion API failed. $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
}
if (!$body) { $body = @() }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
