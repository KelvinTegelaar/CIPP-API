function Invoke-ExecRemoveCippCveException {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter

try {
    # Parse request
    $cveId = $Request.Query.cveId
    $TenantFilter = $Request.Query.TenantFilter
    $removeScope = $Request.Query.removeScope  # "CurrentTenant", "AllAffected", "Global"
    
    if (-not $cveId) {
        throw "cveId is required"
    }
    
    # Get tables
    $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
    $CveCacheTable = Get-CIPPTable -TableName 'CveCache'
    
    # Determine which exceptions to remove
    $ExceptionsToRemove = @()
    
    switch ($removeScope) {
        "CurrentTenant" {
            if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
                throw "Current tenant must be selected"
            }
            $ExceptionsToRemove = @($TenantFilter)
        }
        "AllAffected" {
            # Get all exceptions for this CVE
            $AllExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "PartitionKey eq '$cveId'"
            $ExceptionsToRemove = $AllExceptions | Where-Object { $_.RowKey -ne "ALL" } | Select-Object -ExpandProperty RowKey
        }
        "Global" {
            $ExceptionsToRemove = @("ALL")
        }
        default {
            # If no scope specified, just remove current tenant
            if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
                $ExceptionsToRemove = @($TenantFilter)
            } else {
                throw "removeScope must be specified when no tenant is selected"
            }
        }
    }
    
    $RemovedCount = 0
    
    foreach ($TenantId in $ExceptionsToRemove) {
        # Remove exception from CveExceptions table
        $ExceptionEntity = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "PartitionKey eq '$cveId' and RowKey eq '$TenantId'"
        
        if ($ExceptionEntity) {
            Remove-AzDataTableEntity @CveExceptionsTable -Entity $ExceptionEntity -Force
            $RemovedCount++
            
            # Update CveCache entries
            if ($TenantId -eq "ALL") {
                $CacheFilter = "PartitionKey eq '$cveId'"
            } else {
                $CacheFilter = "PartitionKey eq '$cveId' and customerId eq '$TenantId'"
            }
            
            $CacheEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter $CacheFilter
            
            foreach ($CacheEntry in $CacheEntries) {
                # Check if there are any other exceptions still applying
                $RemainingExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "PartitionKey eq '$cveId' and (RowKey eq 'ALL' or RowKey eq '$($CacheEntry.customerId)')"
                
                if (-not $RemainingExceptions) {
                    $CacheEntry.hasException = $false
                    $CacheEntry.exceptionSource = ""
                } else {
                    # Still has exceptions from other sources
                    $sources = ($RemainingExceptions | Select-Object -ExpandProperty source -Unique) -join '/'
                    $CacheEntry.exceptionSource = $sources
                }
                
                Add-CIPPAzDataTableEntity @CveCacheTable -Entity $CacheEntry -Force
            }
        }
    }
    
    Write-LogMessage -headers $Headers -API $APIName -message "Removed $RemovedCount CVE exception(s) for $cveId" -Sev Info
    
    $StatusCode = [HttpStatusCode]::OK
    $Body = [PSCustomObject]@{
        Results = "Successfully removed $RemovedCount exception(s) for CVE $cveId"
    }
    
} catch {
    $ErrorMessage = Get-CippException -Exception $_
    Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove CVE exception: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
    $StatusCode = [HttpStatusCode]::BadRequest
    $Body = [PSCustomObject]@{
        Results = "Failed to remove exception: $($ErrorMessage.NormalizedError)"
    }
}

return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    })
}
