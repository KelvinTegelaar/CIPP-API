Function Invoke-ListSensitivityLabelTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Security.SensitivityLabel.Read
    .DESCRIPTION
        Lists saved sensitivity label templates for deploying standardized label configurations.
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

    # Purview label priority first (numeric, missing last), then name.
    $Templates = @($Templates | Sort-Object -Property @(
            @{ Expression = { $P = 0.0; [double]::TryParse("$($_.Priority)", [ref]$P) ? $P : [double]::MaxValue } }
            @{ Expression = { $_.DisplayName ?? $_.Name } }
        ))

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
