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
                # TVM also returns software-inventory rows with no CVE. Skip them before the
                # hashtable lookup: ContainsKey($null) throws, which was caught per-record and
                # logged as an 'Allover Build' error for every such row.
                if ([string]::IsNullOrWhiteSpace($CveId)) { $SkippedCount++; return }

                if (-not $CveAggregator.ContainsKey($CveId)) {
                    # Establish global CVE & software properties for this specific tenant
                    $CveAggregator[$CveId] = @{
                        cveId                      = $CveId
                        customerId                 = $TenantFilter
                        softwareVendor             = $Vuln.softwareVendor             ?? ''
                        softwareName               = $Vuln.softwareName               ?? ''
                        softwareVersion            = $Vuln.softwareVersion            ?? ''
                        vulnerabilitySeverityLevel = $Vuln.vulnerabilitySeverityLevel ?? ''
                        exploitabilityLevel        = $Vuln.exploitabilityLevel        ?? ''

                        # Device metadata as the JSON text it will be stored as, not as objects.
                        DeviceJson                 = [System.Text.StringBuilder]::new()
                        DeviceCount                = 0
                        # Dedupe devices by id so DeviceCount is a unique-device count and the
                        # stored list carries each affected device once, however many software
                        # packages reported the same CVE on it.
                        SeenDevices                = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    }
                }

                # Extract this device instance and fold it in as serialised text immediately.
                #
                # The aggregation itself is unavoidable: TVM returns one record per
                # (device x software x CVE), so a CVE's records are scattered across the whole
                # stream and its row cannot be written until the stream ends. What IS avoidable is
                # keeping every record as a live object until then. This previously held one
                # hashtable per record in a List per CVE - on a large tenant that is hundreds of
                # thousands of hashtables, each carrying its own dictionary overhead plus six
                # strings, and it is the single largest thing this job retains.
                #
                # Serialising on arrival keeps the same bytes in one allocation instead of eight,
                # and lets the source record become collectable straight away. It also removes the
                # second copy that used to exist at emit time, where a CVE's whole device List and
                # the JSON produced from it were both live at once.
                #
                # Minimal per-device payload: only the id and name are consumed downstream.
                $DeviceId = ($Vuln.deviceId -join ',') ?? ''
                $DeviceName = ($Vuln.deviceName -join ',') ?? ''

                # Dedupe on the device id (falling back to the name) so one device that reports
                # the same CVE across several software packages is stored and counted once.
                $DeviceKey = if ($DeviceId) { $DeviceId } else { $DeviceName }
                $Bucket = $CveAggregator[$CveId]
                if ($DeviceKey -and $Bucket.SeenDevices.Add($DeviceKey)) {
                    # ConvertTo-Json builds the fragment rather than string interpolation, so
                    # escaping of device names stays correct.
                    $Fragment = @{
                        deviceId   = $DeviceId
                        deviceName = $DeviceName
                    } | ConvertTo-Json -Compress

                    # Appended only after the fragment is fully built, so a record that fails
                    # mid-extraction cannot leave a partial payload attached to the wrong CVE.
                    if ($Bucket.DeviceCount -gt 0) { [void]$Bucket.DeviceJson.Append(',') }
                    [void]$Bucket.DeviceJson.Append($Fragment)
                    $Bucket.DeviceCount++
                }
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

        # Snapshot the keys so buckets can be dropped while iterating - enumerating
        # $CveAggregator.Keys directly and removing from it throws InvalidOperationException.
        $CveKeys = [string[]]$CveAggregator.Keys

        try {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $UniqueCves CVEs" -sev 'Info'

            # A single Add-CIPPDbItem invocation, fed lazily. This is deliberate: the
            # function's end block runs one orphan cleanup keyed to the run id minted in
            # its begin block, and writes DefenderCVEs-Count once. Splitting the flush
            # into several calls would give each chunk its own run id, so each later call's
            # cleanup would treat earlier chunks' rows as orphans as soon as the run
            # exceeded the 5 minute skew margin, and would leave the stored count equal to
            # the final chunk instead of the total.
            & {
                foreach ($CveKey in $CveKeys) {
                    $CveData = $CveAggregator[$CveKey]

                    # The fragments are already JSON; only the surrounding shape is decided here.
                    # A single-device CVE stays a bare object and a multi-device CVE becomes an
                    # array, which is what piping a List through ConvertTo-Json used to produce and
                    # what Get-CIPPCVEReport and the CVE management endpoint parse.
                    $CompactDeviceJson = if ($CveData.DeviceCount -eq 1) {
                        $CveData.DeviceJson.ToString()
                    } else {
                        [void]$CveData.DeviceJson.Insert(0, '[').Append(']')
                        $CveData.DeviceJson.ToString()
                    }

                    @{
                        PartitionKey               = $CveKey
                        RowKey                     = $TenantFilter # blob field only; the table RowKey is derived from 'id' below
                        # Stable table RowKey: Add-CIPPDbItem derives "$Type-$id", so this makes
                        # writes idempotent (DefenderCVEs-<cveId>) instead of a random GUID per
                        # run - which also stopped every run rewriting the whole tenant's rows.
                        id                         = $CveKey
                        customerId                 = $TenantFilter
                        cveId                      = $CveKey
                        softwareVendor             = $CveData.softwareVendor
                        softwareName               = $CveData.softwareName
                        softwareVersion            = $CveData.softwareVersion
                        vulnerabilitySeverityLevel = $CveData.vulnerabilitySeverityLevel
                        exploitabilityLevel        = $CveData.exploitabilityLevel

                        # Unique affected-device count for this CVE in this tenant.
                        deviceCount                = $CveData.DeviceCount

                        # Minimal per-device detail ({deviceId, deviceName}) as one JSON string.
                        deviceDetailsJson          = $CompactDeviceJson

                        lastUpdated                = $LastUpdated
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
        if (Test-CIPPCacheCapabilityError -Message $_.Exception.Message) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Skipping Defender CVE cache - tenant not onboarded to Defender for Endpoint: $($ErrorMessage.NormalizedError)" -sev 'Debug' -LogData $ErrorMessage
            return
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "CVE Cache Refresh failed: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        throw
    }
}
