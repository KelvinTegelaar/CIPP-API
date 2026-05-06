function Invoke-ExecRemoveCippCveException {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName      = $Request.Params.CIPPEndpoint
    $Headers      = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        $CveId       = $Request.Query.cveId      ?? $Request.Body.cveId
        $RemoveScope = $Request.Query.removeScope ?? $Request.Body.removeScope

        if (-not $CveId) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: cveId is required' }
            }
        }

        $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
        $CveCacheTable      = Get-CIPPTable -TableName 'CveCache'

        # Load all exceptions for this CVE once — reused throughout
        $AllCveExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "PartitionKey eq '$CveId'"

        $ExceptionsToRemove = switch ($RemoveScope) {
            'CurrentTenant' {
                if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
                    throw 'Current tenant must be selected'
                }
                @($TenantFilter)
            }
            'AllAffected' {
                @($AllCveExceptions | Where-Object { $_.RowKey -ne 'ALL' } | Select-Object -ExpandProperty RowKey)
            }
            'Global' {
                @('ALL')
            }
            default {
                if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
                    @($TenantFilter)
                } else {
                    throw 'removeScope must be specified when no tenant is selected'
                }
            }
        }

        # Remove matched exception entities
        $EntitiesToRemove = $AllCveExceptions | Where-Object { $_.RowKey -in $ExceptionsToRemove }
        $RemovedCount     = 0

        foreach ($Entity in $EntitiesToRemove) {
            Remove-AzDataTableEntity @CveExceptionsTable -Entity $Entity -Force
            $RemovedCount++
        }

        # Reload exceptions after removal to determine what remains
        $RemainingCveExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "PartitionKey eq '$CveId'"

        # Load all cache entries for this CVE once
        $AllCacheEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter "PartitionKey eq '$CveId'"

        # Filter to only cache entries affected by the removed tenants
        $AffectedCacheEntries = if ($ExceptionsToRemove -contains 'ALL') {
            $AllCacheEntries
        } else {
            $AllCacheEntries | Where-Object { $_.customerId -in $ExceptionsToRemove }
        }

        # Update affected cache entries in batch
        $CacheUpdates = [System.Collections.Generic.List[object]]::new()

        foreach ($CacheEntry in $AffectedCacheEntries) {
            $StillExcepted = $RemainingCveExceptions | Where-Object { $_.RowKey -eq 'ALL' -or $_.RowKey -eq $CacheEntry.customerId }

            if (-not $StillExcepted) {
                $CacheEntry.hasException    = $false
                $CacheEntry.exceptionSource = ''
            } else {
                $CacheEntry.exceptionSource = ($StillExcepted | Select-Object -ExpandProperty source -Unique) -join '/'
            }

            [void]$CacheUpdates.Add($CacheEntry)
        }

        if ($CacheUpdates.Count -gt 0) {
            Add-CIPPAzDataTableEntity @CveCacheTable -Entity $CacheUpdates -Force
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Removed $RemovedCount CVE exception(s) for $CveId" -sev 'Info'

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = "Successfully removed $RemovedCount exception(s) for CVE $CveId" }
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed to remove CVE exception: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed to remove exception: $($ErrorMessage.NormalizedError)" }
        }
    }
}
