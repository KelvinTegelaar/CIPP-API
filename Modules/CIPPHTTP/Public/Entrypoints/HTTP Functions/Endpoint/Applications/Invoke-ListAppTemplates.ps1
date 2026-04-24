function Invoke-ListAppTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'AppTemplate'"
    $RawTemplates = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    $Templates = foreach ($Template in $RawTemplates) {
        try {
            $JSONData = $Template.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
            $Apps = if ($JSONData.Apps) { @($JSONData.Apps) } else { @() }
            [PSCustomObject]@{
                displayName = $JSONData.Displayname
                description = $JSONData.Description
                appCount    = $Apps.Count
                appTypes    = @($Apps | ForEach-Object { $_.appType } | Sort-Object -Unique)
                appNames    = @($Apps | ForEach-Object { $_.appName })
                Apps        = $Apps
                GUID        = $Template.RowKey
            }
        } catch {}
    }

    $Templates = @($Templates | Sort-Object -Property displayName)

    if ($Request.Query.ID) {
        $Templates = $Templates | Where-Object -Property GUID -EQ $Request.Query.ID
    }

    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = ConvertTo-Json -Depth 100 -InputObject @($Templates)
    })
}
