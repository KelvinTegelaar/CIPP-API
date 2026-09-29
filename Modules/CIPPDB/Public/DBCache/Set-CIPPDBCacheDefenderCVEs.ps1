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

        # Tenant-wide device tables. TVM repeats every device once per (software x CVE), so a
        # per-CVE copy of each device's id and JSON text costs ~350-400 bytes per CVE x device
        # pair - hundreds of MB on a large tenant, all retained until the stream ends. Instead
        # each distinct device is stored once and a CVE bucket holds small integer indexes:
        #   $DeviceKeyIndex  dedupe key (id, else name; case-insensitive) -> key index
        #   $FragmentIndex   exact id + name text -> fragment index
        #   $DeviceFragments fragment index -> the {deviceId, deviceName} JSON text
        # Two indexes rather than one because dedupe is case-insensitive but the stored text is
        # whatever the CVE's first record for that device said, exactly as before. Read by index (a
        # missing key is $null), not TryGetValue: a [ref] out-parameter costs several times an index
        # lookup per record.
        $DeviceKeyIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $FragmentIndex = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        $DeviceFragments = [System.Collections.Generic.List[string]]::new()

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

                        # Dedupe key indexes seen on this CVE, so DeviceCount is a unique-device
                        # count and each affected device is stored once however many software
                        # packages reported the CVE on it.
                        SeenDevices                = [System.Collections.Generic.HashSet[int]]::new()
                        # Fragment indexes in first-seen order - the order the row lists them in.
                        Devices                    = [System.Collections.Generic.List[int]]::new()
                    }
                }

                # Minimal per-device payload: only the id and name are consumed downstream.
                $DeviceId = ($Vuln.deviceId -join ',') ?? ''
                $DeviceName = ($Vuln.deviceName -join ',') ?? ''

                # Dedupe on the device id (falling back to the name).
                $DeviceKey = if ($DeviceId) { $DeviceId } else { $DeviceName }
                if (-not $DeviceKey) { return }

                $KeyIndex = $DeviceKeyIndex[$DeviceKey]
                if ($null -eq $KeyIndex) {
                    $KeyIndex = $DeviceKeyIndex.Count
                    $DeviceKeyIndex[$DeviceKey] = $KeyIndex
                }

                $Bucket = $CveAggregator[$CveId]
                if ($Bucket.SeenDevices.Add($KeyIndex)) {
                    $FragmentKey = "$DeviceId`0$DeviceName"
                    $Fragment = $FragmentIndex[$FragmentKey]
                    if ($null -eq $Fragment) {
                        # ConvertTo-Json builds the fragment rather than string interpolation, so
                        # escaping of device names stays correct. Built once per device, not per
                        # CVE x device pair.
                        $DeviceFragments.Add((@{
                                    deviceId   = $DeviceId
                                    deviceName = $DeviceName
                                } | ConvertTo-Json -Compress))
                        $Fragment = $DeviceFragments.Count - 1
                        $FragmentIndex[$FragmentKey] = $Fragment
                    }
                    $Bucket.Devices.Add($Fragment)
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
                    $DeviceCount = $CveData.Devices.Count
                    $Parts = [string[]]::new($DeviceCount)
                    for ($i = 0; $i -lt $DeviceCount; $i++) { $Parts[$i] = $DeviceFragments[$CveData.Devices[$i]] }
                    $CompactDeviceJson = if ($DeviceCount -eq 1) { $Parts[0] } else { '[' + [string]::Join(',', $Parts) + ']' }

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
                        deviceCount                = $DeviceCount

                        # Minimal per-device detail ({deviceId, deviceName}) as one JSON string.
                        deviceDetailsJson          = $CompactDeviceJson

                        lastUpdated                = $LastUpdated
                    }

                    # The row is built; drop the bucket so its index lists are collectable
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
