function Invoke-ListExConnectorTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.Connector.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'templates'

    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'ExConnectorTemplate'"

    if ($Request.Query.ID) {
        $Filter += " and RowKey eq '$($Request.Query.ID)'"
    }

    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)

    if ($Templates) {
        $Templates | ForEach-Object {
            $GUID = $_.RowKey
            $Direction = $_.direction
            $data = $_.JSON | ConvertFrom-Json
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
            $data | Add-Member -NotePropertyName 'cippconnectortype' -NotePropertyValue $Direction -Force
            $data
        } | Sort-Object -Property displayName
    }
    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property RowKey -EQ $Request.query.id }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
