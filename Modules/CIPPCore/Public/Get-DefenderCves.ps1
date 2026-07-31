function get-DefenderCVEs {
    <#
    .SYNOPSIS
        Returns one aggregated row per CVE for a tenant, live from Defender TVM

    .DESCRIPTION
        Defender TVM returns one record per (device x software x CVE) tuple, which for a
        large tenant is hundreds of thousands of rows. This runs on the HTTP worker pool
        (Invoke-ListCVEManagement), so it shares the container's managed heap with the
        background pool and an OOM here takes user-facing requests down with it.

        Raw records are therefore folded into per-CVE buckets as they arrive off the wire.
        The ConvertFrom-Json PSCustomObject graph is by far the most expensive of the
        representations this function would otherwise hold at once - roughly 6.5 KB of a
        ~10 KB per-record peak - and streaming makes it collectable page by page instead of
        keeping every record alive until the return. Each bucket is then dropped as soon as
        its row is built, so the aggregator and the returned entity list never both hold the
        whole tenant.

        Unlike Set-CIPPDBCacheDefenderCVEs the emit stage cannot stream into a writer: the
        caller needs the full set for a single HTTP response. Peak is therefore the entity
        list plus one page, rather than raw records + aggregator + entity list at once.

    .PARAMETER TenantFilter
        The tenant to retrieve vulnerabilities for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        # Group the raw TVM records into unified CVE buckets as they stream in.
        $CveAggregator = @{}
        $RecordCount = 0
        $SkippedCount = 0

        Get-DefenderTvmRaw -TenantId $TenantFilter -Stream | ForEach-Object {
            $Vuln = $_
            $RecordCount++

            try {
                $CveId = $Vuln.cveId

                if (-not $CveAggregator.ContainsKey($CveId)) {
                    # Establish global CVE & software properties for this specific tenant
                    $CveAggregator[$CveId] = @{
                        cveId                        = $CveId
                        customerId                   = $TenantFilter
                        softwareVendor               = $Vuln.softwareVendor               ?? ''
                        softwareName                 = $Vuln.softwareName                 ?? ''
                        vulnerabilitySeverityLevel   = $Vuln.vulnerabilitySeverityLevel   ?? ''
                        recommendedSecurityUpdate    = $Vuln.recommendedSecurityUpdate    ?? ''
                        recommendedSecurityUpdateUrl = $Vuln.recommendedSecurityUpdateUrl ?? ''
                        exploitabilityLevel          = $Vuln.exploitabilityLevel          ?? ''

                        # Arrays to collect device metadata efficiently
                        AffectedDevices              = [System.Collections.Generic.List[object]]::new()
                    }
                }

                # Extract properties specific to this device instance and append in one
                # step, so a record that fails mid-extraction cannot leave a previous
                # record's payload behind to be appended to the wrong CVE.
                [void]$CveAggregator[$CveId].AffectedDevices.Add(@{
                        deviceId        = ($Vuln.deviceId -join ',') ?? ''
                        deviceName      = ($Vuln.deviceName -join ',') ?? ''
                        osVersion       = $Vuln.osVersion ?? ''
                        softwareVersion = ($Vuln.softwareVersion -join ',') ?? ''
                        diskPaths       = if ($Vuln.diskPaths) { $Vuln.diskPaths -join ';' } else { '' }
                        registryPaths   = if ($Vuln.registryPaths) { $Vuln.registryPaths -join ';' } else { '' }
                    })
            } catch {
                $SkippedCount++
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Allover Build: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
            }
        }

        if ($RecordCount -eq 0) {
            Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message 'No vulnerability data returned from Defender TVM' -sev 'Warning'
            return
        }

        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Retrieved $RecordCount CVE records from Defender TVM" -sev 'Info'

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Skipped $SkippedCount malformed CVE record(s) during aggregation" -sev 'Warning'
        }

        if ($CveAggregator.Count -eq 0) {
            Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message 'No valid CVE records to cache' -sev 'Warning'
            return
        }

        # One timestamp for the whole call. The -UFormat string truncates to whole seconds so
        # the per-row values were already near-identical, and the caller surfaces this as a
        # single cacheTimeStamp per CVE.
        $LastUpdated = [string]$(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')

        $Entities = [System.Collections.Generic.List[object]]::new()

        # Snapshot the keys so buckets can be dropped while iterating - enumerating
        # $CveAggregator.Keys directly and removing from it throws InvalidOperationException.
        $CveKeys = [string[]]$CveAggregator.Keys

        foreach ($CveKey in $CveKeys) {
            $CveData = $CveAggregator[$CveKey]

            # Flatten or convert device info arrays into a compact, compressed JSON string.
            # Piped (not -InputObject) so a single-device CVE serialises to an object and a
            # multi-device CVE to an array, exactly as before.
            $CompactDeviceJson = $CveData.AffectedDevices | ConvertTo-Json -Compress

            [void]$Entities.Add(@{
                    PartitionKey                 = $CveKey
                    RowKey                       = $TenantFilter # RowKey becomes just the Tenant, ensuring 1 row per CVE per Tenant
                    customerId                   = $TenantFilter
                    cveId                        = $CveKey
                    softwareVendor               = $CveData.softwareVendor
                    softwareName                 = $CveData.softwareName
                    vulnerabilitySeverityLevel   = $CveData.vulnerabilitySeverityLevel
                    recommendedSecurityUpdate    = $CveData.recommendedSecurityUpdate
                    recommendedSecurityUpdateUrl = $CveData.recommendedSecurityUpdateUrl
                    exploitabilityLevel          = $CveData.exploitabilityLevel

                    # Meta aggregation counts
                    deviceCount                  = $CveData.AffectedDevices.Count

                    # All individual device variations compressed safely inside a single field
                    deviceDetailsJson            = $CompactDeviceJson

                    lastUpdated                  = $LastUpdated
                })

            # The row is built; drop the bucket so its device list is collectable while the
            # rest of the set is still being serialised.
            $CveAggregator.Remove($CveKey)
        }

        # One row per bucket, so this is the unique CVE count without a second pass.
        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Retrieved $($Entities.Count) Unique CVEs" -sev 'Info'

        return $Entities

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "CVE Cache Refresh failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        throw
    }
}
