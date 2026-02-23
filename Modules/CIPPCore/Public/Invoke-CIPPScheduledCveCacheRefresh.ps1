function Invoke-CIPPScheduledCveCacheRefresh {
    <#
    .FUNCTIONALITY
        Entrypoint
    .COMPONENT
        (APIName) CveCacheRefresh
    .SYNOPSIS
        (Label) Refresh CVE Cache from Defender TVM
    .DESCRIPTION
        (Helptext) Pulls Defender TVM vulnerabilities for each tenant and stores them in Azure Tables for faster access and exception management.
        (DocsDescription) This scheduled task queries Microsoft Defender Threat & Vulnerability Management (TVM) for all software vulnerabilities affecting devices in the tenant. Results are stored in the CveCache Azure Table for use by the Vulnerability Management page and NinjaOne sync.
    .NOTES
        CAT
            Scheduled Tasks
        TAG
            Security
        IMPACT
            Low Impact
        ADDEDDATE
            2026-01-08
        RECOMMENDEDBY
            ["CIPP"]
    #>
    param(
        $Tenant
    )

    Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Starting CVE Cache Refresh for tenant" -Sev 'Info'

    try {
        # ============================
        # 1. GET CVE CACHE TABLE CONTEXT
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Getting CveCache table context" -Sev 'Debug'
        
        $CveCacheTable = Get-CIPPTable -TableName 'CveCache'
        
        if (-not $CveCacheTable) {
            throw "Failed to get CveCache table context"
        }

        # ============================
        # 2. QUERY DEFENDER TVM
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Pulling Defender TVM data via Get-DefenderTvmRaw" -Sev 'Debug'
        
        $AllVulns = Get-DefenderTvmRaw -TenantId $Tenant -MaxPages 0
        
        if (-not $AllVulns) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "No vulnerability data returned from Defender TVM" -Sev 'Warning'
            $AllVulns = @()
        }

        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Retrieved $($AllVulns.Count) vulnerability records from Defender TVM" -Sev 'Info'

        if ($AllVulns.Count -eq 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "No vulnerabilities found for this tenant" -Sev 'Info'
            return
        }

        # ============================
        # 3. DELETE OLD ENTRIES FOR THIS TENANT
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Cleaning up old cache entries for tenant" -Sev 'Debug'
        
        try {
            # Get all existing entries for this tenant
            $ExistingEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter "customerId eq '$Tenant'"
            
            if ($ExistingEntries) {
                $DeleteCount = 0
                foreach ($OldEntry in $ExistingEntries) {
                    try {
                        Remove-AzDataTableEntity -Context $CveCacheTable.Context `
                            -PartitionKey $OldEntry.PartitionKey `
                            -RowKey $OldEntry.RowKey `
                            -ErrorAction Stop
                        $DeleteCount++
                    } catch {
                        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                            -message "Failed to delete old entry: $($_.Exception.Message)" -Sev 'Warning'
                    }
                }
                Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                    -message "Deleted $DeleteCount old cache entries" -Sev 'Debug'
            }
        } catch {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                -message "Warning during cleanup: $($_.Exception.Message)" -Sev 'Warning'
        }

        # ============================
        # 4. TRANSFORM TO CACHE ENTITIES
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Transforming CVE data into cache entities" -Sev 'Debug'
        
        $CacheEntities = @()
        $SkippedCount = 0
        $ProcessedCves = @{}

        foreach ($item in $AllVulns) {
            # Validate required fields
            if ([string]::IsNullOrWhiteSpace($item.cveId) -or 
                [string]::IsNullOrWhiteSpace($item.deviceId) -or
                [string]::IsNullOrWhiteSpace($item.customerId)) {
                $SkippedCount++
                continue
            }

            # Use CVE-ID as PartitionKey for efficient querying
            $PartitionKey = $item.cveId
            
            # Use customerId_deviceId as RowKey for uniqueness per tenant/device
            $RowKey = "$($item.customerId)_$($item.deviceId)"

            # Track CVE-tenant combinations for summary
            $CveKey = "$($item.cveId)|$($item.customerId)"
            if (-not $ProcessedCves.ContainsKey($CveKey)) {
                $ProcessedCves[$CveKey] = 0
            }
            $ProcessedCves[$CveKey]++

            # Create entity with all relevant fields
            $Entity = @{
                PartitionKey            = $PartitionKey
                RowKey                  = $RowKey
                cveId                   = $item.cveId
                customerId              = $item.customerId
                deviceId                = $item.deviceId
                deviceName              = if ($item.deviceName) { $item.deviceName } else { "" }
                severity                = if ($item.vulnerabilitySeverityLevel) { $item.vulnerabilitySeverityLevel } else { "Unknown" }
                cvssScore               = if ($item.cvssScore) { [double]$item.cvssScore } else { 0.0 }
                exploitabilityLevel     = if ($item.exploitabilityLevel) { $item.exploitabilityLevel } else { "Unknown" }
                softwareName            = if ($item.softwareName) { $item.softwareName } else { "" }
                softwareVendor          = if ($item.softwareVendor) { $item.softwareVendor } else { "" }
                softwareVersion         = if ($item.softwareVersion) { $item.softwareVersion } else { "" }
                osPlatform              = if ($item.osPlatform) { $item.osPlatform } else { "" }
                firstSeenTimestamp      = if ($item.firstSeenTimestamp) { $item.firstSeenTimestamp } else { "" }
                lastSeenTimestamp       = if ($item.lastSeenTimestamp) { $item.lastSeenTimestamp } else { "" }
                cveMitigationStatus     = if ($item.cveMitigationStatus) { $item.cveMitigationStatus } else { "" }
                securityUpdateAvailable = if ($null -ne $item.securityUpdateAvailable) { [bool]$item.securityUpdateAvailable } else { $false }
                lastUpdated             = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $CacheEntities += $Entity
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                -message "Skipped $SkippedCount vulnerability records due to missing required fields" -Sev 'Warning'
        }

        if ($CacheEntities.Count -eq 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                -message "No valid CVE records to cache" -Sev 'Warning'
            return
        }

        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
            -message "Prepared $($CacheEntities.Count) cache entities from $($AllVulns.Count) raw records" -Sev 'Info'

        # ============================
        # 5. WRITE TO AZURE TABLE
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
            -message "Writing $($CacheEntities.Count) entities to CveCache table" -Sev 'Info'
        
        $SuccessCount = 0
        $FailCount = 0
        $BatchSize = 100  # Process in batches for better performance
        
        for ($i = 0; $i -lt $CacheEntities.Count; $i += $BatchSize) {
            $Batch = $CacheEntities[$i..[Math]::Min($i + $BatchSize - 1, $CacheEntities.Count - 1)]
            
            try {
                Add-CIPPAzDataTableEntity @CveCacheTable `
                    -Entity $Batch `
                    -CreateTableIfNotExists `
                    -OperationType 'UpsertReplace'
                
                $SuccessCount += $Batch.Count
                
                Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                    -message "Batch progress: $SuccessCount/$($CacheEntities.Count) entities written" -Sev 'Debug'
            }
            catch {
                $FailCount += $Batch.Count
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                    -message "Failed to write batch: $ErrorMessage" -Sev 'Error'
            }
        }

        # ============================
        # 6. LOG SUMMARY
        # ============================
        $UniqueCves = ($ProcessedCves.Keys | ForEach-Object { $_.Split('|')[0] } | Select-Object -Unique).Count
        
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
            -message "CVE Cache Refresh completed. Success: $SuccessCount, Failed: $FailCount, Unique CVEs: $UniqueCves" -Sev 'Info'

        # Return summary for logging
        return @{
            TenantId      = $Tenant
            TotalRecords  = $AllVulns.Count
            CachedEntries = $SuccessCount
            FailedEntries = $FailCount
            UniqueCves    = $UniqueCves
            Timestamp     = (Get-Date).ToUniversalTime()
        }

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
            -message "CVE Cache Refresh failed: $ErrorMessage" -Sev 'Error'
        throw $ErrorMessage
    }
}
