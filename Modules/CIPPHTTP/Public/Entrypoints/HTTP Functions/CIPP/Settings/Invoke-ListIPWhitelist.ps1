Function Invoke-ListIPWhitelist {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant,TenantGroup
    .ROLE
        CIPP.IPDatabase.Read
    .DESCRIPTION
        Lists CIPP's IP allow/block list: every tenant or AllTenants entry with its address or CIDR range (Range) and state (Trusted, Blocked or NotTrusted).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'trustedIps'
    $Rows = @(Get-CIPPAzDataTableEntity @Table)
    # AllTenants entries apply to every tenant, so everyone sees them; tenant entries only to that tenant's admins
    $body = @(@($Rows.Where({ $_.PartitionKey -eq 'AllTenants' })) + @($Rows.Where({ $_.PartitionKey -ne 'AllTenants' }) | Select-CippAllowedTenantData -TenantProperty PartitionKey) | ForEach-Object {
            # Rows from before ranges existed carry the address only in RowKey
            if (-not $_.Range) { $_ | Add-Member -NotePropertyName 'Range' -NotePropertyValue ([string]$_.RowKey -replace '_', '/') -Force }
            $_
        })

    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($body)
        }
}
