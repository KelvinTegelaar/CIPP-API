function Invoke-ListEnrollmentRestrictionTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Autopilot.Read
    .DESCRIPTION
        Lists the saved enrollment (device type) restriction templates with their platform settings, priority and assignment. Pass ID to return a single template. These are CIPP templates, not a tenant's deployed restrictions.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $ID = $Request.Query.ID ?? $Request.Query.id

    $Table = Get-CippTable -tablename 'templates'
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'EnrollmentRestrictionTemplate'") | ForEach-Object {
        try {
            $Template = $_.JSON | ConvertFrom-Json -ErrorAction Stop
            $Template | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.RowKey -Force
            $Template
        } catch {
            Write-Information "Skipping unreadable enrollment restriction template $($_.RowKey)"
        }
    } | Sort-Object -Property platform, displayName

    if ($ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $ID }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })
}
