using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"
Set-Location (Get-Item $PSScriptRoot).Parent.FullName

$Table = Get-CippTable -tablename 'templates'

$Templates = Get-ChildItem "Config\*.IntuneTemplate.json" | ForEach-Object {
    $Entity = @{
        JSON         = "$(Get-Content $_)"
        RowKey       = "$($_.name)"
        PartitionKey = "IntuneTemplate"
        GUID         = "$($_.name)"
    }
    Add-AzDataTableEntity @Table -Entity $Entity -Force
}

#List new policies
$Table = Get-CippTable -tablename 'templates'
$Filter = "PartitionKey eq 'IntuneTemplate'" 
$Templates = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
if ($Request.query.View) {
    $Templates = $Templates | ForEach-Object {
        $data = $_.RAWJson | ConvertFrom-Json
        $data | Add-Member -NotePropertyName "displayName" -NotePropertyValue $_.Displayname
        $data | Add-Member -NotePropertyName "description" -NotePropertyValue $_.Description
        $data | Add-Member -NotePropertyName "Type" -NotePropertyValue $_.Type
        $data | Add-Member -NotePropertyName "GUID" -NotePropertyValue $_.GUID
        $data 
    }
}

if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property guid -EQ $Request.query.id }


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Templates)
    })
