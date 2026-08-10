function Invoke-ExecAddTrustedIP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $tenantfilter = $Request.Query.tenantfilter
    if (-not $tenantfilter) {
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ results = "Missing required query parameter 'tenantfilter'" }
        })
    }

    $tenantDomain = (Get-Tenants -TenantFilter $tenantfilter).defaultDomainName
    if (-not $tenantDomain) {
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ results = "Invalid tenantfilter '$tenantfilter'" }
        })
    }

    $Table = Get-CippTable -tablename 'trustedIps'
    foreach ($IP in $Request.body.IP) {
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = $tenantDomain
            RowKey       = $IP
            state        = $Request.Body.State
        } -Force
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ results = "Added $($Request.Body.IP) to database with state $($Request.Body.State) for $($tenantDomain)" }
        })
}
