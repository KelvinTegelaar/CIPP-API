function Invoke-CIPPScheduledCveCacheRefresh {
    <#
    .SYNOPSIS
        Refresh CVE Cache from Defender TVM
    .DESCRIPTION
        Pulls Defender TVM vulnerabilities for each tenant and stores them in the CveCache Azure Table.
    #>
    param(
        [string]$TenantFilter
    )

    Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Starting CVE Cache Refresh" -Sev 'Info'

    try {
        # ============================
        # 1. GET CVE CACHE TABLE
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Getting CveCache table context" -Sev 'Debug'
        
        $CveCacheTable = Get-CIPPTable -TableName 'CveCache'

        # ============================
        # 2. PULL CVE DATA FROM DEFENDER TVM
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Pulling CVE data from Defender TVM" -Sev 'Debug'
        
        $AllVulns = Get-DefenderTvmRaw -TenantId $TenantFilter -MaxPages 0
        
        if (-not $AllVulns) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "No vulnerability data returned from Defender TVM" -Sev 'Warning'
            return
        }

        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) CVE records from Defender TVM" -Sev 'Info'

        # ============================
        # 3. DELETE OLD ENTRIES FOR THIS TENANT
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Removing old cache entries for this tenant" -Sev 'Debug'
        
        try {
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
                        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                            -message "Failed to delete old entry: $($_.Exception.Message)" -Sev 'Warning'
                    }
                }
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                    -message "Deleted $DeleteCount old cache entries" -Sev 'Debug'
            }
        } catch {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                -message "Warning during cleanup: $($_.Exception.Message)" -Sev 'Warning'
        }

        # ============================
        # 4. WRITE NEW ENTRIES TO TABLE
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Writing CVE data to cache table" -Sev 'Debug'
        
        $Entities = @()
        $SkippedCount = 0

        foreach ($vuln in $AllVulns) {
            # Skip if missing required fields
            if ([string]::IsNullOrWhiteSpace($vuln.cveId) -or 
                [string]::IsNullOrWhiteSpace($vuln.deviceName)) {
                $SkippedCount++
                continue
            }

            # Create table entity using actual API field names
            # PartitionKey = CVE ID (for efficient querying by CVE)
            # RowKey = TenantFilter_deviceName (unique per tenant per device)
            $Entity = @{
                PartitionKey                 = $vuln.cveId
                RowKey                       = "$TenantFilter`_$($vuln.deviceName)"
                # Add customerId from TenantFilter parameter
                customerId                   = $TenantFilter
                # Store all fields from API response as-is
                id                           = if ($vuln.id) { $vuln.id } else { "" }
                deviceId                     = $vuln.deviceId
                deviceName                   = if ($vuln.deviceName) { $vuln.deviceName } else { "" }
                osPlatform                   = if ($vuln.osPlatform) { $vuln.osPlatform } else { "" }
                osVersion                    = if ($vuln.osVersion) { $vuln.osVersion } else { "" }
                osArchitecture               = if ($vuln.osArchitecture) { $vuln.osArchitecture } else { "" }
                softwareVendor               = if ($vuln.softwareVendor) { $vuln.softwareVendor } else { "" }
                softwareName                 = if ($vuln.softwareName) { $vuln.softwareName } else { "" }
                softwareVersion              = if ($vuln.softwareVersion) { $vuln.softwareVersion } else { "" }
                cveId                        = $vuln.cveId
                vulnerabilitySeverityLevel   = if ($vuln.vulnerabilitySeverityLevel) { $vuln.vulnerabilitySeverityLevel } else { "" }
                recommendedSecurityUpdate    = if ($vuln.recommendedSecurityUpdate) { $vuln.recommendedSecurityUpdate } else { "" }
                recommendedSecurityUpdateId  = if ($vuln.recommendedSecurityUpdateId) { $vuln.recommendedSecurityUpdateId } else { "" }
                recommendedSecurityUpdateUrl = if ($vuln.recommendedSecurityUpdateUrl) { $vuln.recommendedSecurityUpdateUrl } else { "" }
                diskPaths                    = if ($vuln.diskPaths) { ($vuln.diskPaths -join ';') } else { "" }
                registryPaths                = if ($vuln.registryPaths) { ($vuln.registryPaths -join ';') } else { "" }
                lastSeenTimestamp            = if ($vuln.lastSeenTimestamp) { $vuln.lastSeenTimestamp } else { "" }
                firstSeenTimestamp           = if ($vuln.firstSeenTimestamp) { $vuln.firstSeenTimestamp } else { "" }
                exploitabilityLevel          = if ($vuln.exploitabilityLevel) { $vuln.exploitabilityLevel } else { "" }
                recommendationReference      = if ($vuln.recommendationReference) { $vuln.recommendationReference } else { "" }
                rbacGroupName                = if ($vuln.rbacGroupName) { $vuln.rbacGroupName } else { "" }
                lastUpdated                  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $Entities += $Entity
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                -message "Skipped $SkippedCount records due to missing required fields" -Sev 'Warning'
        }

        if ($Entities.Count -eq 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                -message "No valid CVE records to cache" -Sev 'Warning'
            return
        }

        # ============================
        # 5. BATCH WRITE TO TABLE
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
            -message "Writing $($Entities.Count) entities to CveCache table" -Sev 'Info'
        
        $SuccessCount = 0
        $FailCount = 0
        $BatchSize = 100
        
        for ($i = 0; $i -lt $Entities.Count; $i += $BatchSize) {
            $Batch = $Entities[$i..[Math]::Min($i + $BatchSize - 1, $Entities.Count - 1)]
            
            try {
                Add-CIPPAzDataTableEntity @CveCacheTable `
                    -Entity $Batch `
                    -CreateTableIfNotExists `
                    -OperationType 'UpsertReplace'
                
                $SuccessCount += $Batch.Count
            }
            catch {
                $FailCount += $Batch.Count
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                    -message "Failed to write batch: $ErrorMessage" -Sev 'Error'
            }
        }

        # ============================
        # 6. LOG COMPLETION
        # ============================
        $UniqueCves = ($Entities | Select-Object -ExpandProperty cveId -Unique).Count
        
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
            -message "CVE Cache Refresh completed. Success: $SuccessCount, Failed: $FailCount, Unique CVEs: $UniqueCves" -Sev 'Info'

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
            -message "CVE Cache Refresh failed: $ErrorMessage" -Sev 'Error'
        throw $ErrorMessage
    }
}
