using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Set-Location (Get-Item $PSScriptRoot).Parent.FullName

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host $Request.query.id
#Migrating old policies whenever you do a list
$Table = Get-CippTable -tablename 'templates'

$Templates = Get-ChildItem "Config\*.CATemplate.json" | ForEach-Object {
    $Entity = @{
        JSON         = "$(Get-Content $_)"
        RowKey       = "$($_.name)"
        PartitionKey = "CATemplate"
        GUID         = "$($_.name)"
    }
    Add-AzDataTableEntity @Table -Entity $Entity -Force
}

#List new policies
$Table = Get-CippTable -tablename 'templates'
$Filter = "PartitionKey eq 'CATemplate'" 
$Templates = (Get-AzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
    $data = $_.JSON | ConvertFrom-Json -Depth 100
    $data | Add-Member -NotePropertyName "GUID" -NotePropertyValue $_.GUID -Force
    $data 
} | Sort-Object -Property displayName

if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.id }

$Templates = ConvertTo-Json -InputObject @($Templates) -Depth 100
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Templates
    })
