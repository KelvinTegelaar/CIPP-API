function Invoke-ListJITRoleTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Role.Read
    .DESCRIPTION
        Lists JIT Role Templates - named allow-lists of directory roles used to restrict which roles a
        CIPP custom role may assign via JIT Admin.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'JITRoleTemplate'"

    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        try {
            $row = $_
            $data = $row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $row.GUID -Force
            $data | Add-Member -NotePropertyName 'RowKey' -NotePropertyValue $row.RowKey -Force
            $data
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to process JIT Role template: $($row.RowKey) - $($_.Exception.Message)" -sev 'Warning'
        }
    }

    $Templates = $Templates | Sort-Object -Property templateName

    # If a specific GUID is requested, filter to that template
    if ($Request.query.GUID) {
        $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.GUID
    }

    $Templates = ConvertTo-Json -InputObject @($Templates) -Depth 100

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Templates
        })
}
