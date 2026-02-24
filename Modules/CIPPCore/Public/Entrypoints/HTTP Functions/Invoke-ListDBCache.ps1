function Invoke-ListDBCache {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param (
        $Request,
        $TriggerMetadata
    )

    $TenantFilter = $Request.Query.tenantFilter
    $Type = $Request.Query.type

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: tenantFilter query parameter is required' }
            })
    }

    if (-not $Type) {
        $Types = Get-CIPPDbItem -CountsOnly -TenantFilter $TenantFilter | Select-Object -ExpandProperty RowKey
        $Types = $Types | ForEach-Object { $_ -replace '-Count$', '' } | Sort-Object

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{
                    Results        = 'Error: type query parameter is required'
                    AvailableTypes = $Types
                }
            })
    }

    $Tenant = Get-Tenants -TenantFilter $TenantFilter
    if ($Tenant) {
        $Results = New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })
}
