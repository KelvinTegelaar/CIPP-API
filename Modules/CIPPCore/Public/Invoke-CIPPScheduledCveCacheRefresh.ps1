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

    Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Starting CVE Cache Refresh" -Sev 'Info'

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
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "No vulnerability data returned from Defender TVM" -Sev 'Warning'
            return
        }

        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Retrieved $($AllVulns.Count) CVE records from Defender TVM" -Sev 'Info'

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
                    }
                    catch {
                        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Failed to delete old entry: $($_.Exception.Message)" -Sev 'Warning'
                    }
                }
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Cleared $DeleteCount old cache entries" -Sev 'Debug'
            }
        }
        catch {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Warning during cache cleanup: $($_.Exception.Message)" -Sev 'Warning'
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
                foreach ($exception in $TenantExceptions) {
                    if (-not $CippExceptions.ContainsKey($exception.cveId)) {
                        $CippExceptions[$exception.cveId] = $true
                    }
                }
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "$($CippExceptions.Count) CVE exception(s) active for this tenant" -Sev 'Debug'
            }
        }
        catch {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Could not retrieve CIPP exceptions: $($_.Exception.Message)" -Sev 'Warning'
        }

        # ============================
        # 6. BUILD ENTITIES
        # ============================
        $Entities     = @()
        $SkippedCount = 0

        foreach ($vuln in $AllVulns) {
            if ([string]::IsNullOrWhiteSpace($vuln.cveId) -or [string]::IsNullOrWhiteSpace($vuln.deviceName)) {
                $SkippedCount++
                continue
            }

            $hasDefenderException = $DefenderExceptions.ContainsKey($vuln.cveId)
            $hasCippException     = $CippExceptions.ContainsKey($vuln.cveId)
            $hasException         = $hasDefenderException -or $hasCippException

            $exceptionSource = if ($hasDefenderException -and $hasCippException) { 'Both' }
                               elseif ($hasDefenderException) { 'Defender' }
                               elseif ($hasCippException)     { 'CIPP' }
                               else                           { '' }

            $Entities += @{
                PartitionKey                 = $vuln.cveId
                RowKey                       = "$TenantFilter`_$($vuln.deviceName)"
                customerId                   = $TenantFilter
                id                           = if ($vuln.id)                           { $vuln.id }                           else { '' }
                deviceId                     = if ($vuln.deviceId)                     { $vuln.deviceId }                     else { '' }
                deviceName                   = if ($vuln.deviceName)                   { $vuln.deviceName }                   else { '' }
                osPlatform                   = if ($vuln.osPlatform)                   { $vuln.osPlatform }                   else { '' }
                osVersion                    = if ($vuln.osVersion)                    { $vuln.osVersion }                    else { '' }
                osArchitecture               = if ($vuln.osArchitecture)               { $vuln.osArchitecture }               else { '' }
                softwareVendor               = if ($vuln.softwareVendor)               { $vuln.softwareVendor }               else { '' }
                softwareName                 = if ($vuln.softwareName)                 { $vuln.softwareName }                 else { '' }
                softwareVersion              = if ($vuln.softwareVersion)              { $vuln.softwareVersion }              else { '' }
                cveId                        = $vuln.cveId
                vulnerabilitySeverityLevel   = if ($vuln.vulnerabilitySeverityLevel)   { $vuln.vulnerabilitySeverityLevel }   else { '' }
                recommendedSecurityUpdate    = if ($vuln.recommendedSecurityUpdate)    { $vuln.recommendedSecurityUpdate }    else { '' }
                recommendedSecurityUpdateId  = if ($vuln.recommendedSecurityUpdateId)  { $vuln.recommendedSecurityUpdateId }  else { '' }
                recommendedSecurityUpdateUrl = if ($vuln.recommendedSecurityUpdateUrl) { $vuln.recommendedSecurityUpdateUrl } else { '' }
                diskPaths                    = if ($vuln.diskPaths)                    { $vuln.diskPaths -join ';' }          else { '' }
                registryPaths                = if ($vuln.registryPaths)               { $vuln.registryPaths -join ';' }      else { '' }
                lastSeenTimestamp            = if ($vuln.lastSeenTimestamp)            { $vuln.lastSeenTimestamp }            else { '' }
                firstSeenTimestamp           = if ($vuln.firstSeenTimestamp)           { $vuln.firstSeenTimestamp }           else { '' }
                exploitabilityLevel          = if ($vuln.exploitabilityLevel)          { $vuln.exploitabilityLevel }          else { '' }
                recommendationReference      = if ($vuln.recommendationReference)      { $vuln.recommendationReference }      else { '' }
                rbacGroupName                = if ($vuln.rbacGroupName)                { $vuln.rbacGroupName }                else { '' }
                hasException                 = $hasException
                exceptionSource              = $exceptionSource
                lastUpdated                  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Skipped $SkippedCount records (missing cveId or deviceName)" -Sev 'Warning'
        }

        if ($Entities.Count -eq 0) {
            Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "No valid CVE records to cache" -Sev 'Warning'
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
            }
            catch {
                $FailCount    += $Batch.Count
                $ErrorMessage  = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "Batch $BatchNumber/$TotalBatches failed: $ErrorMessage" -Sev 'Error'
            }
        }

        # ============================
        # 8. COMPLETION LOG
        # ============================
        $UniqueCves    = ($Entities | Select-Object -ExpandProperty cveId -Unique).Count
        $ExceptedCount = ($Entities | Where-Object { $_.hasException -eq $true }).Count

        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "CVE Cache Refresh complete — $UniqueCves unique CVEs cached ($ExceptedCount excepted). Written: $SuccessCount, Failed: $FailCount" -Sev 'Info'

    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'CveCacheRefresh' -tenant $TenantFilter -message "CVE Cache Refresh failed: $ErrorMessage" -Sev 'Error'
        throw $ErrorMessage
    }
}
