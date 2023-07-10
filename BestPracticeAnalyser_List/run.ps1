using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$Tenants = Get-Tenants
$Table = get-cipptable 'cachebpa'
$Results = (Get-AzDataTableEntity @Table) | ForEach-Object { 
    $_.UnusedLicenseList = @(ConvertFrom-Json -ErrorAction silentlycontinue -InputObject $_.UnusedLicenseList)
    $_
}

if (!$Results) {
    $Results = @{
        Tenant = "The BPA has not yet run."
    }
}
Write-Host ($Tenants | ConvertTo-Json)
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @(($Results | Where-Object -Property RowKey -In $Tenants.customerId))
    })