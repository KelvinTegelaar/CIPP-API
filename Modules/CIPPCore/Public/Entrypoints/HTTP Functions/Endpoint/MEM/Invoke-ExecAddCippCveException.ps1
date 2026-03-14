function Invoke-ExecAddCippCveException {
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
    # Parse request body
    $Body = $Request.Body
    
    $cveId = $Body.cveId
    $exceptionType = $Body.exceptionType
    $applyTo = $Body.applyTo
    $justification = $Body.justification
    $expiryDate = $Body.expiryDate
    $TenantFilter = $Request.Query.TenantFilter
    
    # Validate required fields
    if (-not $cveId -or -not $exceptionType -or -not $applyTo -or -not $justification) {
        throw "Missing required fields: cveId, exceptionType, applyTo, and justification are required"
    }
    
    # Get tables
    $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'
    $CveCacheTable = Get-CIPPTable -TableName 'CveCache'
    
    # Determine which tenants to apply the exception to
    $TenantsToUpdate = @()
    
    switch ($applyTo) {
        "CurrentTenant" {
            if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
                throw "Current tenant must be selected to use 'Current Tenant Only' option"
            }
            $TenantsToUpdate = @($TenantFilter)
        }
        "AllAffected" {
            # Get all affected tenants for this CVE
            $AffectedEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter "PartitionKey eq '$cveId'"
            $TenantsToUpdate = $AffectedEntries | Select-Object -ExpandProperty customerId -Unique
        }
        "Global" {
            # Global exception - use "ALL" as tenant identifier
            $TenantsToUpdate = @("ALL")
        }
    }
    
    Write-Host "Applying exception to tenants: $($TenantsToUpdate -join ', ')"
    
    # Get current user from headers
    $Username = $Headers.'x-ms-client-principal'
    $CurrentDate = (Get-Date).ToUniversalTime().ToString('o')
    
    # Create exception entries
    $ExceptionsAdded = @()
    $ExceptionsUpdated = @()
    
    foreach ($TenantId in $TenantsToUpdate) {
        # Check if exception already exists
        $ExistingException = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "PartitionKey eq '$cveId' and RowKey eq '$TenantId'"
        
        $ExceptionEntity = @{
            PartitionKey            = $cveId
            RowKey                  = $TenantId
            cveId                   = $cveId
            customerId              = $TenantId
            exceptionType           = $exceptionType
            exceptionComment        = $justification
            exceptionCreatedBy      = $Username
            exceptionCreatedDate    = $CurrentDate
            exceptionExpiry         = $expiryDate
            source                  = "CIPP"
        }
        
        # Add or update exception
        Add-CIPPAzDataTableEntity @CveExceptionsTable -Entity $ExceptionEntity -CreateTableIfNotExists -OperationType 'UpsertReplace' -Force
        
        if ($ExistingException) {
            $ExceptionsUpdated += $TenantId
        } else {
            $ExceptionsAdded += $TenantId
        }
    }
    
    # Now update the CveCache entries to reflect the exception
    foreach ($TenantId in $TenantsToUpdate) {
        if ($TenantId -eq "ALL") {
            # Global exception - update all entries for this CVE
            $CacheFilter = "PartitionKey eq '$cveId'"
        } else {
            # Specific tenant - update only entries for this tenant
            $CacheFilter = "PartitionKey eq '$cveId' and customerId eq '$TenantId'"
        }
        
        $CacheEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter $CacheFilter
        
        foreach ($CacheEntry in $CacheEntries) {
            $CacheEntry.hasException = $true
            $CacheEntry.exceptionSource = "CIPP"
            
            Add-CIPPAzDataTableEntity @CveCacheTable -Entity $CacheEntry -CreateTableIfNotExists -OperationType 'UpsertReplace' -Force
        }
    }
    
    Write-LogMessage -headers $Headers -API $APIName -message "Added/updated CVE exception for $cveId across $($TenantsToUpdate.Count) tenant(s)" -Sev Info
    
    $StatusCode = [HttpStatusCode]::OK
    $Body = [PSCustomObject]@{
        Results = "Successfully applied exception to CVE $cveId"
        TenantsAffected = $TenantsToUpdate.Count
        ExceptionsAdded = $ExceptionsAdded.Count
        ExceptionsUpdated = $ExceptionsUpdated.Count
        Details = "Added: $($ExceptionsAdded -join ', '), Updated: $($ExceptionsUpdated -join ', ')"
    }
    
} catch {
    $ErrorMessage = Get-CippException -Exception $_
    Write-LogMessage -headers $Headers -API $APIName -message "Failed to add CVE exception: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
    $StatusCode = [HttpStatusCode]::BadRequest
    $Body = [PSCustomObject]@{
        Results = "Failed to add exception: $($ErrorMessage.NormalizedError)"
    }
}

return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    })
}
