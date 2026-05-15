Function Invoke-ListSensitivityLabelTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Security.SensitivityLabel.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'SensitivityLabelTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $GUID = $_.RowKey
        $data = $_.JSON | ConvertFrom-Json
        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
        $data
    }

    if ($Request.Query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.Query.ID }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
