using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$RawGraphRequest = if ($TenantFilter -ne 'AllTenants') {
    $GraphRequest = Get-CIPPLicenseOverview -TenantFilter $TenantFilter
}
else {
    $Table = Get-CIPPTable -TableName cachelicenses
    $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
    if (!$Rows) {
        Push-OutputBinding -Name Msg -Value (Get-Date).ToString()
        $GraphRequest = [PSCustomObject]@{
            Tenant  = 'Loading data for all tenants. Please check back in 1 minute'
            License = 'Loading data for all tenants. Please check back in 1 minute'
        }
    }         
    else {
        $GraphRequest = $Rows
    }
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    }) -Clobber