Function Invoke-ListConnectionFilterTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.ConnectionFilter.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'templates'

    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'ConnectionfilterTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $GUID = $_.RowKey
        $data = $_.JSON | ConvertFrom-Json
        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID
        $data
    }

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property RowKey -EQ $Request.query.id }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
