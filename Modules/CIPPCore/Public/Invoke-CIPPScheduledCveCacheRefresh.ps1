function Invoke-CIPPScheduledCveCacheRefresh {
    <#
    .SYNOPSIS
        Refresh CVE Cache from Defender TVM
    .DESCRIPTION
        Pulls Defender TVM vulnerabilities for each tenant and stores them in the CveCache Azure Table.
    #>
    param(
        $Tenant
    )

    Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Starting CVE Cache Refresh" -Sev 'Info'

    try {
        # ============================
        # 1. GET CVE CACHE TABLE
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Getting CveCache table context" -Sev 'Debug'
        
        $CveCacheTable = Get-CIPPTable -TableName 'CveCache'

        # ============================
        # 2. PULL CVE DATA FROM DEFENDER TVM
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Pulling CVE data from Defender TVM" -Sev 'Debug'
        
        $AllVulns = Get-DefenderTvmRaw -TenantId $Tenant -MaxPages 0
        
        if (-not $AllVulns) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "No vulnerability data returned from Defender TVM" -Sev 'Warning'
            return
        }

        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Retrieved $($AllVulns.Count) CVE records from Defender TVM" -Sev 'Info'

        # ============================
        # 3. DELETE OLD ENTRIES FOR THIS TENANT
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Removing old cache entries for this tenant" -Sev 'Debug'
        
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
        # 4. WRITE NEW ENTRIES TO TABLE
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant -message "Writing CVE data to cache table" -Sev 'Debug'
        
        $Entities = @()
        $SkippedCount = 0

        foreach ($vuln in $AllVulns) {
            # Skip if missing required fields
            if ([string]::IsNullOrWhiteSpace($vuln.cveId) -or 
                [string]::IsNullOrWhiteSpace($vuln.deviceId) -or
                [string]::IsNullOrWhiteSpace($vuln.customerId)) {
                $SkippedCount++
                continue
            }

            # Create table entity
            # PartitionKey = CVE ID (for efficient querying by CVE)
            # RowKey = customerId_deviceId (unique per tenant per device)
            $Entity = @{
                PartitionKey            = $vuln.cveId
                RowKey                  = "$($vuln.customerId)_$($vuln.deviceId)"
                cveId                   = $vuln.cveId
                customerId              = $vuln.customerId
                deviceId                = $vuln.deviceId
                deviceName              = if ($vuln.deviceName) { $vuln.deviceName } else { "" }
                severity                = if ($vuln.vulnerabilitySeverityLevel) { $vuln.vulnerabilitySeverityLevel } else { "" }
                cvssScore               = if ($vuln.cvssScore) { [double]$vuln.cvssScore } else { 0.0 }
                exploitabilityLevel     = if ($vuln.exploitabilityLevel) { $vuln.exploitabilityLevel } else { "" }
                softwareName            = if ($vuln.softwareName) { $vuln.softwareName } else { "" }
                softwareVendor          = if ($vuln.softwareVendor) { $vuln.softwareVendor } else { "" }
                softwareVersion         = if ($vuln.softwareVersion) { $vuln.softwareVersion } else { "" }
                osPlatform              = if ($vuln.osPlatform) { $vuln.osPlatform } else { "" }
                firstSeenTimestamp      = if ($vuln.firstSeenTimestamp) { $vuln.firstSeenTimestamp } else { "" }
                lastSeenTimestamp       = if ($vuln.lastSeenTimestamp) { $vuln.lastSeenTimestamp } else { "" }
                securityUpdateAvailable = if ($null -ne $vuln.securityUpdateAvailable) { [bool]$vuln.securityUpdateAvailable } else { $false }
                lastUpdated             = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $Entities += $Entity
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                -message "Skipped $SkippedCount records due to missing required fields" -Sev 'Warning'
        }

        if ($Entities.Count -eq 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                -message "No valid CVE records to cache" -Sev 'Warning'
            return
        }

        # ============================
        # 5. BATCH WRITE TO TABLE
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
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
                Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
                    -message "Failed to write batch: $ErrorMessage" -Sev 'Error'
            }
        }

        # ============================
        # 6. LOG COMPLETION
        # ============================
        $UniqueCves = ($Entities | Select-Object -ExpandProperty cveId -Unique).Count
        
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
            -message "CVE Cache Refresh completed. Success: $SuccessCount, Failed: $FailCount, Unique CVEs: $UniqueCves" -Sev 'Info'

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'CveCacheRefresh' -tenant $Tenant `
            -message "CVE Cache Refresh failed: $ErrorMessage" -Sev 'Error'
        throw $ErrorMessage
    }
}
