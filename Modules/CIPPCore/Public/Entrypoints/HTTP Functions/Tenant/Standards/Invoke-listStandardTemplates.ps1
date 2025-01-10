using namespace System.Net

Function Invoke-listStandardTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $data = $_.JSON | ConvertFrom-Json -Depth 100
        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
        $data
    } | Sort-Object -Property templateName

    if ($Request.query.id) { $Templates = $Templates | Where-Object GUID -EQ $Request.query.id }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
