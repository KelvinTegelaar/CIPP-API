Function Invoke-ListTenantAllowBlockListTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Lists saved Tenant Allow/Block List templates for Exchange Online Protection.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'TenantAllowBlockListTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $GUID = $_.RowKey
        $data = $_.JSON | ConvertFrom-Json
        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
        $data
    }

    if ($Request.query.ID) {
        $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.ID
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })
}
