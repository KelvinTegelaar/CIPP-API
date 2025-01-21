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

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $JSON = $_.JSON
        try {
            $RowKey = $_.RowKey
            $data = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
        } catch {
            Write-Host "$($RowKey)"
            return
        }
        $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
        if ($data.excludedTenants) { $data.excludedTenants = @($data.excludedTenants) }
        $data
    } | Sort-Object -Property templateName

    if ($Request.query.id) { $Templates = $Templates | Where-Object GUID -EQ $Request.query.id }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
