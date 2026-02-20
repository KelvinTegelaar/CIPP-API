function Invoke-ListIntuneReusableSettingTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneReusableSettingTemplate'"

    if ($Request.query.ID) {
        $EscapedId = $Request.query.ID -replace "'", "''"  # escape OData quotes
        $Filter = "PartitionKey eq 'IntuneReusableSettingTemplate' and RowKey eq '$EscapedId'"
    }

    $RawTemplates = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    $Templates = foreach ($Item in $RawTemplates) {
        $Parsed = $null
        if ($Item.JSON) {
            $Parsed = $Item.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
        }

        $DisplayName = $Parsed.DisplayName ?? $Parsed.displayName ?? $Item.DisplayName ?? $Item.RowKey
        $Description = $Parsed.Description ?? $Parsed.description ?? $Item.Description
        $RawJSON = $Parsed.RawJSON ?? $Item.RawJSON
        [PSCustomObject]@{
            displayName = $DisplayName
            description = $Description
            GUID        = $Item.RowKey
            RawJSON     = $RawJSON
            isSynced    = -not [string]::IsNullOrEmpty($Item.SHA)
        }
    }

    $Templates = $Templates | Sort-Object -Property displayName

    return ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
