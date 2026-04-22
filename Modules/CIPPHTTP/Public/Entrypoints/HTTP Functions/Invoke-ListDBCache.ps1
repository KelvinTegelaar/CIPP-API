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

    $Tenant = (Get-Tenants -TenantFilter $TenantFilter).defaultDomainName

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: tenantFilter query parameter is required' }
            })
    }

    if (-not $Type) {
        $Types = Get-CIPPDbItem -CountsOnly -TenantFilter $Tenant | Select-Object -ExpandProperty RowKey
        $Types = $Types | ForEach-Object { $_ -replace '-Count$', '' } | Sort-Object

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{
                    Results        = 'Error: type query parameter is required'
                    AvailableTypes = $Types
                }
            })
    }

    if ($Type -eq '_availableTypes') {
        $Types = Get-CIPPDbItem -CountsOnly -TenantFilter $Tenant | Select-Object -ExpandProperty RowKey
        $Types = $Types | ForEach-Object { $_ -replace '-Count$', '' } | Sort-Object
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = @($Types) }
            })
    }

    if ($Tenant) {
        $Results = New-CIPPDbRequest -TenantFilter $Tenant -Type $Type
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })
}
