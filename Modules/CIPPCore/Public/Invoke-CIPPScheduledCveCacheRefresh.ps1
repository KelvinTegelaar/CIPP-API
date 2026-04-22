function Invoke-CIPPScheduledCveCacheRefresh {
    <#
    .SYNOPSIS
        Refresh CVE Cache from Defender TVM
    .DESCRIPTION
        Pulls Defender TVM vulnerabilities for a single tenant and stores them
        in the CveCache Azure Table. Called by the CIPP scheduler once per tenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter
    )

    Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Starting CVE Cache Refresh" -sev 'Info'

    try {
        # ============================
        # 1. GET TABLE REFERENCES
        # ============================
        $CveCacheTable      = Get-CIPPTable -TableName 'CveCache'
        $CveExceptionsTable = Get-CIPPTable -TableName 'CveExceptions'

        # ============================
        # 2. PULL CVE DATA FROM DEFENDER TVM
        # ============================
        $AllVulns = Get-DefenderTvmRaw -TenantId $TenantFilter -MaxPages 0

        if (-not $AllVulns) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "No vulnerability data returned from Defender TVM" -sev 'Warning'
            return
        }

        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) CVE records from Defender TVM" -sev 'Info'

        # ============================
        # 3. DELETE OLD ENTRIES FOR THIS TENANT
        # ============================
        try {
            $ExistingEntries = Get-CIPPAzDataTableEntity @CveCacheTable -Filter "customerId eq '$TenantFilter'"

            if ($ExistingEntries) {
                $DeleteCount = 0
                foreach ($OldEntry in $ExistingEntries) {
                    try {
                        Remove-AzDataTableEntity @CveCacheTable -Entity $OldEntry -Force
                        $DeleteCount++
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Failed to delete old entry: $($ErrorMessage.NormalizedError)" -sev 'Warning' -LogData $ErrorMessage
                    }
                }
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Cleared $DeleteCount old cache entries" -sev 'Debug'
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Warning during cache cleanup: $($ErrorMessage.NormalizedError)" -sev 'Warning' -LogData $ErrorMessage
        }

        # ============================
        # 4. DEFENDER EXCEPTION STATUS (DISABLED — CAUSES OOM ON LARGE TENANTS)
        # ============================
        # TODO: Re-enable with pagination once OOM issue is resolved.
        $DefenderExceptions = @{}

        # ============================
        # 5. GET CIPP EXCEPTIONS FOR THIS TENANT
        # ============================
        $CippExceptions = @{}

        try {
            $TenantExceptions = Get-CIPPAzDataTableEntity @CveExceptionsTable -Filter "customerId eq '$TenantFilter' or customerId eq 'ALL'"

            if ($TenantExceptions) {
                foreach ($Exception in $TenantExceptions) {
                    if (-not $CippExceptions.ContainsKey($Exception.cveId)) {
                        $CippExceptions[$Exception.cveId] = $true
                    }
                }
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "$($CippExceptions.Count) CVE exception(s) active for this tenant" -sev 'Debug'
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Could not retrieve CIPP exceptions: $($ErrorMessage.NormalizedError)" -sev 'Warning' -LogData $ErrorMessage
        }

        # ============================
        # 6. BUILD ENTITIES
        # ============================
        $Entities     = [System.Collections.Generic.List[object]]::new()
        $SkippedCount = 0

        foreach ($Vuln in $AllVulns) {
            if ([string]::IsNullOrWhiteSpace($Vuln.cveId) -or [string]::IsNullOrWhiteSpace($Vuln.deviceName)) {
                $SkippedCount++
                continue
            }

            $HasDefenderException = $DefenderExceptions.ContainsKey($Vuln.cveId)
            $HasCippException     = $CippExceptions.ContainsKey($Vuln.cveId)
            $HasException         = $HasDefenderException -or $HasCippException

            $ExceptionSource = if ($HasDefenderException -and $HasCippException) { 'Both' }
                               elseif ($HasDefenderException) { 'Defender' }
                               elseif ($HasCippException)     { 'CIPP' }
                               else                           { '' }

            [void]$Entities.Add(@{
                PartitionKey                 = $Vuln.cveId
                RowKey                       = "$TenantFilter`_$($Vuln.deviceName)"
                customerId                   = $TenantFilter
                id                           = $Vuln.id                           ?? ''
                deviceId                     = $Vuln.deviceId                     ?? ''
                deviceName                   = $Vuln.deviceName                   ?? ''
                osPlatform                   = $Vuln.osPlatform                   ?? ''
                osVersion                    = $Vuln.osVersion                    ?? ''
                osArchitecture               = $Vuln.osArchitecture               ?? ''
                softwareVendor               = $Vuln.softwareVendor               ?? ''
                softwareName                 = $Vuln.softwareName                 ?? ''
                softwareVersion              = $Vuln.softwareVersion              ?? ''
                cveId                        = $Vuln.cveId
                vulnerabilitySeverityLevel   = $Vuln.vulnerabilitySeverityLevel   ?? ''
                recommendedSecurityUpdate    = $Vuln.recommendedSecurityUpdate    ?? ''
                recommendedSecurityUpdateId  = $Vuln.recommendedSecurityUpdateId  ?? ''
                recommendedSecurityUpdateUrl = $Vuln.recommendedSecurityUpdateUrl ?? ''
                diskPaths                    = if ($Vuln.diskPaths)     { $Vuln.diskPaths -join ';' }     else { '' }
                registryPaths                = if ($Vuln.registryPaths) { $Vuln.registryPaths -join ';' } else { '' }
                lastSeenTimestamp            = $Vuln.lastSeenTimestamp            ?? ''
                firstSeenTimestamp           = $Vuln.firstSeenTimestamp           ?? ''
                exploitabilityLevel          = $Vuln.exploitabilityLevel          ?? ''
                recommendationReference      = $Vuln.recommendationReference      ?? ''
                rbacGroupName                = $Vuln.rbacGroupName                ?? ''
                hasException                 = $HasException
                exceptionSource              = $ExceptionSource
                lastUpdated                  = [string]$(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
            })
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Skipped $SkippedCount records (missing cveId or deviceName)" -sev 'Warning'
        }

        if ($Entities.Count -eq 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "No valid CVE records to cache" -sev 'Warning'
            return
        }

        # ============================
        # 7. BATCH WRITE TO TABLE
        # ============================
        $SuccessCount = 0
        $FailCount    = 0
        $BatchSize    = 50
        $TotalBatches = [Math]::Ceiling($Entities.Count / $BatchSize)

        for ($i = 0; $i -lt $Entities.Count; $i += $BatchSize) {
            $BatchNumber = [Math]::Floor($i / $BatchSize) + 1
            $Batch       = $Entities[$i..[Math]::Min($i + $BatchSize - 1, $Entities.Count - 1)]

            try {
                Add-CIPPAzDataTableEntity @CveCacheTable -Entity $Batch -Force
                $SuccessCount += $Batch.Count
            } catch {
                $ErrorMessage  = Get-CippException -Exception $_
                $FailCount    += $Batch.Count
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Batch $BatchNumber/$TotalBatches failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
            }
        }

        # ============================
        # 8. COMPLETION LOG
        # ============================
        $UniqueCves    = ($Entities | Select-Object -ExpandProperty cveId -Unique).Count
        $ExceptedCount = ($Entities | Where-Object { $_.hasException -eq $true }).Count

        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "CVE Cache Refresh complete — $UniqueCves unique CVEs cached ($ExceptedCount excepted). Written: $SuccessCount, Failed: $FailCount" -sev 'Info'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "CVE Cache Refresh failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        throw
    }
}
