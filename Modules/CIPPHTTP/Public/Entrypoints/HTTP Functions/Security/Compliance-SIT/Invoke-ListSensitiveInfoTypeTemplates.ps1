Function Invoke-ListSensitiveInfoTypeTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Security.SensitiveInfoType.Read
    .DESCRIPTION
        Lists saved sensitive information type templates for deploying custom SIT configurations.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'SensitiveInfoTypeTemplate'"
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
