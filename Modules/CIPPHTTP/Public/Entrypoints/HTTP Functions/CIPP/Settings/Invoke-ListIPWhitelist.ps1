Function Invoke-ListIPWhitelist {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.IPDatabase.Read
    .DESCRIPTION
        Lists CIPP's IP allow/block list: every tenant or AllTenants entry with its address or CIDR range (Range) and state (Trusted, Blocked or NotTrusted).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'trustedIps'
    $body = @(Get-CIPPAzDataTableEntity @Table | ForEach-Object {
            # Rows from before ranges existed carry the address only in RowKey
            if (-not $_.Range) { $_ | Add-Member -NotePropertyName 'Range' -NotePropertyValue ([string]$_.RowKey -replace '_', '/') -Force }
            $_
        })

    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($body)
        }
}
