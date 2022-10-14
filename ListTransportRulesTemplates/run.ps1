using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
$Table = Get-CippTable -tablename 'templates'

$Templates = Get-ChildItem "Config\*.TransportRuleTemplate.json" | ForEach-Object {
    
    $Entity = @{
        JSON         = "$(Get-Content $_)"
        RowKey       = "$($_.name)"
        PartitionKey = "TransportTemplate"
        GUID         = "$($_.name)"
    }
    Add-AzDataTableEntity @Table -Entity $Entity -Force

}

#List new policies
$Table = Get-CippTable -tablename 'templates'
$Filter = "PartitionKey eq 'TransportTemplate'" 
$Templates = (Get-AzDataTableRow @Table -Filter $Filter) | ForEach-Object {
    $GUID = $_.RowKey
    $data = $_.JSON | ConvertFrom-Json 
    $data | Add-Member -NotePropertyName "GUID" -NotePropertyValue $GUID
    $data 
}

if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property RowKey -EQ $Request.query.id }


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Templates)
    })
