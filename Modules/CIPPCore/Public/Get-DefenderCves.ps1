function get-DefenderCVEs {
    <#
    .SYNOPSIS
        Returns one aggregated row per CVE for a tenant, live from Defender TVM

    .DESCRIPTION
        Defender TVM returns one record per (device x software x CVE) tuple, which for a
        large tenant is hundreds of thousands of rows. This runs on the HTTP worker pool
        (Invoke-ListCVEManagement), so it shares the container's managed heap with the
        background pool and an OOM here takes user-facing requests down with it.

        Both stages stream, mirroring Set-CIPPDBCacheDefenderCVEs:

          1. Raw records are folded into per-CVE buckets as they arrive off the wire, with
             each device's metadata serialised immediately to the JSON text it will be
             returned as. The ConvertFrom-Json PSCustomObject graph - by far the most
             expensive of the representations this function would otherwise hold, roughly
             6.5 KB of a ~10 KB per-record peak - is collectable page by page, and the
             aggregator holds one string per CVE instead of a hashtable per record.
          2. Rows are emitted straight to the pipeline as they are built. The caller folds
             them one at a time, and each bucket is dropped as soon as its row is emitted,
             so the aggregator and the emitted row set never both hold the whole tenant.

        Peak is therefore the aggregated JSON text plus one page, rather than raw records
        + aggregator + a fully materialised entity list all at once.

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
                # Skip TVM software-inventory rows with no CVE before the hashtable lookup;
                # ContainsKey($null) throws and was logged per-record as an 'Allover Build' error.
                if ([string]::IsNullOrWhiteSpace($CveId)) { $SkippedCount++; return }

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

                        # Device metadata as the JSON text it will be returned as, not as objects.
                        DeviceJson                   = [System.Text.StringBuilder]::new()
                        DeviceCount                  = 0
                    }
                }

                # Extract this device instance and fold it in as serialised text immediately -
                # see Set-CIPPDBCacheDefenderCVEs for the full rationale. Keeping one hashtable
                # per record alive until the stream ends is the single largest thing this
                # function would otherwise retain, and this path runs per user request.
                #
                # ConvertTo-Json builds the fragment rather than string interpolation, so
                # escaping of device names and registry paths stays correct.
                $Fragment = @{
                    deviceId        = ($Vuln.deviceId -join ',') ?? ''
                    deviceName      = ($Vuln.deviceName -join ',') ?? ''
                    osVersion       = $Vuln.osVersion ?? ''
                    softwareVersion = ($Vuln.softwareVersion -join ',') ?? ''
                    diskPaths       = if ($Vuln.diskPaths) { $Vuln.diskPaths -join ';' } else { '' }
                    registryPaths   = if ($Vuln.registryPaths) { $Vuln.registryPaths -join ';' } else { '' }
                } | ConvertTo-Json -Compress

                # Appended only after the fragment is fully built, so a record that fails
                # mid-extraction cannot leave a partial payload attached to the wrong CVE.
                $Bucket = $CveAggregator[$CveId]
                if ($Bucket.DeviceCount -gt 0) { [void]$Bucket.DeviceJson.Append(',') }
                [void]$Bucket.DeviceJson.Append($Fragment)
                $Bucket.DeviceCount++
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

        # One row per bucket, so this is the unique CVE count without a second pass. Logged
        # before the emit loop because the buckets are consumed as rows go out.
        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "Retrieved $($CveAggregator.Count) Unique CVEs" -sev 'Info'

        # Snapshot the keys so buckets can be dropped while iterating - enumerating
        # $CveAggregator.Keys directly and removing from it throws InvalidOperationException.
        $CveKeys = [string[]]$CveAggregator.Keys

        foreach ($CveKey in $CveKeys) {
            $CveData = $CveAggregator[$CveKey]

            # The fragments are already JSON; only the surrounding shape is decided here.
            # A single-device CVE stays a bare object and a multi-device CVE becomes an
            # array, which is what piping a List through ConvertTo-Json used to produce and
            # what Invoke-ListCVEManagement parses.
            $CompactDeviceJson = if ($CveData.DeviceCount -eq 1) {
                $CveData.DeviceJson.ToString()
            } else {
                [void]$CveData.DeviceJson.Insert(0, '[').Append(']')
                $CveData.DeviceJson.ToString()
            }

            # Emitted straight to the pipeline: the caller merges each row as it arrives,
            # so no entity list ever materialises here.
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
                deviceCount                  = $CveData.DeviceCount

                # All individual device variations compressed safely inside a single field
                deviceDetailsJson            = $CompactDeviceJson

                lastUpdated                  = $LastUpdated
            }

            # The row is emitted; drop the bucket so its device JSON is collectable once
            # the caller has folded the row.
            $CveAggregator.Remove($CveKey)
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'DefenderCVEs' -tenant $TenantFilter -message "CVE Cache Refresh failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        throw
    }
}
