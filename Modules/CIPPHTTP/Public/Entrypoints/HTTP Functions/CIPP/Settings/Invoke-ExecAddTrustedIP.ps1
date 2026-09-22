function Invoke-ExecAddTrustedIP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $tenantfilter = $Request.Query.tenantfilter
    if (-not $tenantfilter) {
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ results = "Missing required query parameter 'tenantfilter'" }
        })
    }

    $tenantDomain = if ($tenantfilter -eq 'AllTenants') { 'AllTenants' }
    else { (Get-Tenants -TenantFilter $tenantfilter).defaultDomainName }
    if (-not $tenantDomain) {
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ results = "Invalid tenantfilter '$tenantfilter'" }
        })
    }

    try {
        $Table = Get-CippTable -tablename 'trustedIps'
        foreach ($IP in $Request.body.IP) {
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = $tenantDomain
                RowKey       = $IP
                state        = $Request.Body.State
            } -Force
        }
        $Result = "Added $($Request.Body.IP) to database with state $($Request.Body.State) for $($tenantDomain)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $tenantDomain -message $Result -Sev 'Info'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ results = $Result }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to add trusted IP(s) for $($tenantDomain): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $tenantDomain -message $Result -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ results = $Result }
            })
    }
}
