function Invoke-RemoveTenantCapabilitiesCache {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Get the tenant identifier from query parameters
    $DefaultDomainName = $Request.Query.defaultDomainName
    if (-not $DefaultDomainName) {
        $body = [pscustomobject]@{'Results' = 'Missing required parameter: defaultDomainName' }
        $StatusCode = [HttpStatusCode]::BadRequest
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = $body
            })
        return
    }

    try {
        # Get the CacheCapabilities table
        $Table = Get-CippTable -tablename 'CacheCapabilities'

        # Find the cache entry for this tenant
        $Filter = "PartitionKey eq 'Capabilities' and RowKey eq '$DefaultDomainName'"
        $CacheEntry = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey

        if ($CacheEntry) {
            # Remove the cache entry
            Remove-AzDataTableEntity -Force @Table -Entity $CacheEntry
            Write-LogMessage -Headers $Headers -API $APIName -message "Removed capabilities cache for tenant $DefaultDomainName." -Sev 'Info'
            $body = [pscustomobject]@{'Results' = "Successfully removed capabilities cache for tenant $DefaultDomainName" }
            $StatusCode = [HttpStatusCode]::OK
        } else {
            Write-LogMessage -Headers $Headers -API $APIName -message "No capabilities cache found for tenant $DefaultDomainName." -Sev 'Info'
            $body = [pscustomobject]@{'Results' = "No capabilities cache found for tenant $DefaultDomainName" }
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -message "Failed to remove capabilities cache for tenant $DefaultDomainName. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $body = [pscustomobject]@{'Results' = "Failed to remove capabilities cache: $($ErrorMessage.NormalizedError)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
