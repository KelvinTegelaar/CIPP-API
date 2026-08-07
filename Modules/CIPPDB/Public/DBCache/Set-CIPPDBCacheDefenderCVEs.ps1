function Set-CIPPDBCacheDefenderCVEs {
    <#
    .SYNOPSIS
        Caches all vulnerabilities devices for a tenant

    .DESCRIPTION
        Defender TVM returns one record per (device x software x CVE) tuple, which for a
        large tenant is hundreds of thousands of rows. Both stages here stream so that no
        stage ever holds a second full copy of that dataset:

          1. Raw records are folded into per-CVE buckets as they arrive off the wire, so
             the ConvertFrom-Json PSCustomObject graph (the most expensive of the three
             representations) is collectable immediately instead of living until the end
             of the run.
          2. Rows are emitted one CVE at a time straight into a single Add-CIPPDbItem
             pipeline, which already flushes to the table every 100 rows. Each bucket is
             dropped from the aggregator as soon as its row is serialised.

        Peak is therefore the aggregated CVE set plus one page plus one 100-row batch,
        rather than raw records + aggregator + fully materialised entity list all at once.

    .PARAMETER TenantFilter
        The tenant to cache vulnerabilities for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
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
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Allover Build: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
            }
        }

        if ($RecordCount -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No vulnerability data returned from Defender TVM" -sev 'Warning'
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Retrieved $RecordCount CVE records from Defender TVM" -sev 'Debug'

        if ($SkippedCount -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Skipped $SkippedCount malformed CVE record(s) during aggregation" -sev 'Warning'
        }

        if ($CveAggregator.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No valid CVE records to cache" -sev 'Warning'
            return
        }

        $UniqueCves = $CveAggregator.Count

        # One timestamp for the whole run. The -UFormat string truncates to whole seconds
        # so per-row values were already near-identical, and Get-CIPPCVEReport surfaces
        # this as a per-run cacheTimeStamp.
        $LastUpdated = [string]$(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')

        # Snapshot the keys so buckets can be dropped while iterating — enumerating
        # $CveAggregator.Keys directly and removing from it throws InvalidOperationException.
        $CveKeys = [string[]]$CveAggregator.Keys

        try {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $UniqueCves CVEs" -sev 'Info'

            # A single Add-CIPPDbItem invocation, fed lazily. This is deliberate: the
            # function's end block runs one orphan cleanup against the RunStartUtc captured
            # in its begin block, and writes DefenderCVEs-Count once. Splitting the flush
            # into several calls would make each later call's cleanup delete rows written by
            # earlier ones as soon as the run exceeded the 5 minute skew margin, and would
            # leave the stored count equal to the final chunk instead of the total.
            & {
                foreach ($CveKey in $CveKeys) {
                    $CveData = $CveAggregator[$CveKey]

                    # Flatten or convert device info arrays into a compact, compressed JSON string.
                    # Piped (not -InputObject) so a single-device CVE serialises to an object and a
                    # multi-device CVE to an array, exactly as before.
                    $CompactDeviceJson = $CveData.AffectedDevices | ConvertTo-Json -Compress

                    @{
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
                    }

                    # The row is built; drop the bucket so its device list is collectable
                    # before the next CVE is serialised.
                    $CveAggregator.Remove($CveKey)
                }
            } | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DefenderCVEs' -AddCount
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "CVE Cache failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "CVE Cache Refresh failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        throw
    }
}
