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

        # Get exceptions table for checking CIPP exceptions
        $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'

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
            $ExistingEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter "customerId eq '$TenantFilter'"
            
            if ($ExistingEntries) {
                $DeleteCount = 0
                foreach ($OldEntry in $ExistingEntries) {
                    try {
                        Remove-AzDataTableEntity @CveCacheTable -Entity $OldEntry -Force
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
        # 4. GET DEFENDER EXCEPTION STATUS (TEMPORARILY DISABLED - CAUSES OOM)
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Skipping Defender exception check (disabled temporarily)" -Sev 'Debug'
        
        $DefenderExceptions = @{}
        # DISABLED: This query causes Out of Memory exceptions for large tenants
        # Will re-enable with pagination later
        # try {
        #     $uri = 'https://api.securitycenter.microsoft.com/api/Vulnerabilities'
        #     $scope = 'https://api.securitycenter.microsoft.com/.default'
        #     $VulnResponse = New-GraphGetRequest -tenantid $TenantFilter -uri $uri -scope $scope
        #     if ($VulnResponse) {
        #         foreach ($vuln in $VulnResponse) {
        #             if ($vuln.status -eq 'UnderException' -or $vuln.status -eq 'PartialException') {
        #                 $DefenderExceptions[$vuln.id] = $vuln.status
        #             }
        #         }
        #     }
        # } catch {
        #     Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
        #         -message "Warning: Could not retrieve Defender exception status: $($_.Exception.Message)" -Sev 'Warning'
        # }

        # ============================
        # 5. GET CIPP EXCEPTIONS FOR THIS TENANT
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Checking CIPP exceptions" -Sev 'Debug'
        
        $CippExceptions = @{}
        try {
            # Get all CIPP exceptions for this tenant (including global "ALL" exceptions)
            $TenantExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "customerId eq '$TenantFilter' or customerId eq 'ALL'"
            
            if ($TenantExceptions) {
                foreach ($exception in $TenantExceptions) {
                    if (-not $CippExceptions.ContainsKey($exception.cveId)) {
                        $CippExceptions[$exception.cveId] = $true
                    }
                }
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                    -message "Found $($CippExceptions.Count) CVEs with CIPP exceptions" -Sev 'Debug'
            }
        } catch {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                -message "Warning: Could not retrieve CIPP exceptions: $($_.Exception.Message)" -Sev 'Warning'
        }

        # ============================
        # 6. WRITE NEW ENTRIES TO TABLE
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

            # Determine exception status
            $hasDefenderException = $DefenderExceptions.ContainsKey($vuln.cveId)
            $hasCippException = $CippExceptions.ContainsKey($vuln.cveId)
            
            $hasException = $hasDefenderException -or $hasCippException
            
            if ($hasDefenderException -and $hasCippException) {
                $exceptionSource = "Both"
            } elseif ($hasDefenderException) {
                $exceptionSource = "Defender"
            } elseif ($hasCippException) {
                $exceptionSource = "CIPP"
            } else {
                $exceptionSource = ""
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
                deviceId                     = if ($vuln.deviceId) { $vuln.deviceId } else { "" }
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
                # NEW: Exception tracking fields
                hasException                 = $hasException
                exceptionSource              = $exceptionSource
                lastUpdated                  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $Entities += $Entity
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                -message "Skipped $SkippedCount records due to missing required fields (cveId or deviceName)" -Sev 'Warning'
        } else {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                -message "No records skipped - all $($Entities.Count) records are valid" -Sev 'Info'
        }

        if ($Entities.Count -eq 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                -message "No valid CVE records to cache" -Sev 'Warning'
            return
        }

        # ============================
        # 7. BATCH WRITE TO TABLE
        # ============================
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
            -message "Starting batch write of $($Entities.Count) entities to CveCache table" -Sev 'Info'
        
        $SuccessCount = 0
        $FailCount = 0
        $BatchSize = 50  # Reduced from 100 for better reliability
        $TotalBatches = [Math]::Ceiling($Entities.Count / $BatchSize)
        
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
            -message "Writing in $TotalBatches batches of up to $BatchSize records each" -Sev 'Info'
        
        for ($i = 0; $i -lt $Entities.Count; $i += $BatchSize) {
            $BatchNumber = [Math]::Floor($i / $BatchSize) + 1
            $Batch = $Entities[$i..[Math]::Min($i + $BatchSize - 1, $Entities.Count - 1)]
            
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                -message "Writing batch $BatchNumber/$TotalBatches (records $($i + 1) to $($i + $Batch.Count))" -Sev 'Info'
            
            try {
                Add-CIPPAzDataTableEntity @CveCacheTable `
                    -Entity $Batch `
                    -CreateTableIfNotExists `
                    -OperationType 'UpsertReplace'
                
                $SuccessCount += $Batch.Count
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                    -message "Batch $BatchNumber/$TotalBatches completed successfully ($($Batch.Count) records)" -Sev 'Debug'
            }
            catch {
                $FailCount += $Batch.Count
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
                    -message "Batch $BatchNumber/$TotalBatches FAILED: $ErrorMessage" -Sev 'Error'
            }
        }
        
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
            -message "Batch write complete. Total written: $SuccessCount, Total failed: $FailCount" -Sev 'Info'

        # ============================
        # 8. LOG COMPLETION
        # ============================
        $UniqueCves = ($Entities | Select-Object -ExpandProperty cveId -Unique).Count
        $ExceptedCount = ($Entities | Where-Object { $_.hasException -eq $true }).Count
        
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
            -message "CVE Cache Refresh completed. Success: $SuccessCount, Failed: $FailCount, Unique CVEs: $UniqueCves, Excepted: $ExceptedCount" -Sev 'Info'

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter `
            -message "CVE Cache Refresh failed: $ErrorMessage" -Sev 'Error'
        throw $ErrorMessage
    }
}
