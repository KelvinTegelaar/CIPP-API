using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

if ($Request.query.TenantFilter -ne 'AllTenants') {
    $GraphRequest = Get-CIPPMFAState -TenantFilter $Request.query.TenantFilter
}
else {
    $Table = Get-CIPPTable -TableName cachemfa

    $Rows = Get-AzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-2)
    if (!$Rows) {
        $Queue = New-CippQueueEntry -Name 'MFA Users - All Tenants' -Link '/identity/reports/mfa-report?customerId=AllTenants'
        Write-Information ($Queue | ConvertTo-Json)
        Push-OutputBinding -Name Msg -Value $Queue.RowKey
        $GraphRequest = [PSCustomObject]@{
            UPN = 'Loading data for all tenants. Please check back in 10 minutes'
        }
    }         
    else {
        $GraphRequest = $Rows
    }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })
