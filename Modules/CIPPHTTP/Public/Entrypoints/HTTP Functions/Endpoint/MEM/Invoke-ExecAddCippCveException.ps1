function Invoke-ExecAddCippCveException {
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
        $CveId         = [string]$Request.Body.cveId
        $ExceptionType = [string]$Request.Body.exceptionType
        $ApplyTo       = [string]$Request.Body.applyTo
        $Justification = [string]$Request.Body.justification
        $ExpiryDate    = if ($Request.Body.expiryDate) { [string]$Request.Body.expiryDate } else { $null }

        if (-not $CveId -or -not $ExceptionType -or -not $ApplyTo -or -not $Justification) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Error: cveId, exceptionType, applyTo, and justification are required' }
            }
        }

        $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
        $CveCacheTable      = Get-CIPPTable -TableName 'CveCache'

        # Load all existing exceptions for this CVE once
        $AllCveExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "PartitionKey eq '$CveId'"

        $TenantsToUpdate = switch ($ApplyTo) {
            'CurrentTenant' {
                if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
                    throw "Current tenant must be selected to use 'Current Tenant Only' option"
                }
                @($TenantFilter)
            }
            'AllAffected' {
                $AffectedEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter "PartitionKey eq '$CveId'"
                @($AffectedEntries | Select-Object -ExpandProperty customerId -Unique)
            }
            'Global' {
                @('ALL')
            }
            default {
                throw "Invalid applyTo value: $ApplyTo"
            }
        }

        $Username     = $Headers.'x-ms-client-principal-name'
        $CurrentDate  = (Get-Date).ToUniversalTime().ToString('o')
        $ReadableDate = (Get-Date).ToString()

        $ExceptionsAdded   = [System.Collections.Generic.List[string]]::new()
        $ExceptionsUpdated = [System.Collections.Generic.List[string]]::new()

        # Build all exception entities in memory, track add vs update
        $ExceptionEntities = foreach ($TenantId in $TenantsToUpdate) {
            $ExistingException = $AllCveExceptions | Where-Object { $_.RowKey -eq $TenantId }

            if ($ExistingException) {
                [void]$ExceptionsUpdated.Add($TenantId)
            } else {
                [void]$ExceptionsAdded.Add($TenantId)
            }

            @{
                PartitionKey          = [string]$CveId
                RowKey                = [string]$TenantId
                cveId                 = [string]$CveId
                customerId            = [string]$TenantId
                exceptionType         = [string]$ExceptionType
                exceptionComment      = [string]$Justification
                exceptionCreatedBy    = [string]$Username
                exceptionCreatedDate  = [string]$CurrentDate
                exceptionReadableDate = [string]$ReadableDate
                exceptionExpiry       = $ExpiryDate ?? ''
                source                = 'CIPP'
            }
        }

        # Write all exception entities in one batch
        if (@($ExceptionEntities).Count -gt 0) {
            Add-CIPPAzDataTableEntity @CveExceptionsTable -Entity @($ExceptionEntities) -Force
        }

        # Load all cache entries for this CVE once
        $AllCacheEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter "PartitionKey eq '$CveId'"

        # Filter to affected cache entries
        $AffectedCacheEntries = if ($TenantsToUpdate -contains 'ALL') {
            $AllCacheEntries
        } else {
            $AllCacheEntries | Where-Object { $_.customerId -in $TenantsToUpdate }
        }

        # Update affected cache entries in memory then write as one batch
        $CacheUpdates = [System.Collections.Generic.List[object]]::new()

        foreach ($CacheEntry in $AffectedCacheEntries) {
            $CacheEntry.hasException    = $true
            $CacheEntry.exceptionSource = 'CIPP'
            [void]$CacheUpdates.Add($CacheEntry)
        }

        if ($CacheUpdates.Count -gt 0) {
            Add-CIPPAzDataTableEntity @CveCacheTable -Entity $CacheUpdates -Force
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Added/updated CVE exception for $CveId across $($TenantsToUpdate.Count) tenant(s)" -sev 'Info'

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results           = "Successfully applied exception to CVE $CveId"
                TenantsAffected   = $TenantsToUpdate.Count
                ExceptionsAdded   = $ExceptionsAdded.Count
                ExceptionsUpdated = $ExceptionsUpdated.Count
                Details           = "Added: $($ExceptionsAdded -join ', '), Updated: $($ExceptionsUpdated -join ', ')"
            }
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed to add CVE exception: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed to add exception: $($ErrorMessage.NormalizedError)" }
        }
    }
}
