using namespace System.Net

Function Invoke-ListExConnectorTemplates {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Table = Get-CippTable -tablename 'templates'

    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'ExConnectorTemplate'" 
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $GUID = $_.RowKey
        $Direction = $_.direction
        $data = $_.JSON | ConvertFrom-Json 
        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID
        $data | Add-Member -NotePropertyName 'cippconnectortype' -NotePropertyValue $Direction
        $data 
    }

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property RowKey -EQ $Request.query.id }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
