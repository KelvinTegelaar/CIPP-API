using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


$Table = get-cipptable 'cachebpa'
$Results = (Get-AzDataTableRow @Table) | ForEach-Object { 
    $_.UnusedLicenseList = $_.UnusedLicenseList | ConvertFrom-Json -ErrorAction silentlycontinue
    $_
}

if (!$Results) {
    $Results = @{
        Tenant = "The BPA has not yet run."
    }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    })