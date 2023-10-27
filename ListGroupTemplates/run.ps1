using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Set-Location (Get-Item $PSScriptRoot).Parent.FullName

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host $Request.query.id

#List new policies
$Table = Get-CippTable -tablename 'templates'
$Filter = "PartitionKey eq 'GroupTemplate'" 
$Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
    $data = $_.JSON | ConvertFrom-Json 
    $data 
} | Sort-Object -Property displayName

if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.id }


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Templates)
    })
