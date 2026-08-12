function Add-CIPPDbItem {
    <#
    .SYNOPSIS
        Add items to the CIPP Reporting database
    .FUNCTIONALITY
        Internal

    .PARAMETER ClearOnEmpty
        Authorizes removal of every row this run did not write, including when InputObject
        is an authoritative empty collection (which clears the type entirely). Callers must
        only use this after a successful source response.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantFilter,

        [Parameter(Mandatory)]
        [string]$Type,

        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('Data')]
        [AllowNull()]
        [AllowEmptyCollection()]
        $InputObject,

        [switch]$Count,
        [switch]$AddCount,
        [switch]$Append,
        [switch]$ClearOnEmpty,

        [ValidateRange(0, 60)]
        [int]$SkewMarginMinutes = 5
    )

    begin {
        $Table = Get-CippTable -tablename 'CippReportingDB'
        $BatchSize = 100
        $Batch = [System.Collections.Generic.List[hashtable]]::new($BatchSize)
        # Track batch duplicates separately from the full authoritative run used for cleanup.
        $SeenInBatch = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Every row written this run is stamped with this id, and the cleanup below deletes only
        # rows that do NOT carry it. Identity, not age: a run of any length can never delete its
        # own writes, however the worker's and the storage service's clocks disagree. It also
        # means nothing per-row is retained across the run - a previous design kept a HashSet of
        # every row key written for -ClearOnEmpty, which on a tenant-wide streaming cache was
        # tens of thousands of strings held purely to be compared once at the end.
        $RunId = [guid]::NewGuid().ToString()
        # Allow for storage timestamp lag before considering untouched rows stale.
        $RunStartUtc = [DateTimeOffset]::UtcNow.AddMinutes(-$SkewMarginMinutes)

        $TotalProcessed = 0
        # Cache regex instances so each row pays only the match cost, not regex compilation.
        # Two passes preserve the original semantics: path/wildcard chars → '_', control chars → stripped.
        $RowKeyPathRegex = [regex]::new('[/\\#?]')
        $RowKeyControlRegex = [regex]::new('[\u0000-\u001F\u007F-\u009F]')

        if ($TenantFilter -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
            try {
                $TenantLookup = @(Get-Tenants -TenantFilter $TenantFilter -IncludeErrors)
                if ($TenantLookup.Count -gt 0) { $TenantFilter = $TenantLookup[0].defaultDomainName }
            } catch {}
        }
    }

    process {
        if ($null -eq $InputObject) { return }

        if ($Count.IsPresent) {
            if ($InputObject -is [int]) { $TotalProcessed = $InputObject } else { $TotalProcessed += @($InputObject).Count }
            return
        }

        foreach ($Item in @($InputObject)) {
            if ($null -eq $Item) { continue }
            $ItemId = $Item.ExternalDirectoryObjectId ?? $Item.id ?? $Item.Identity ?? $Item.skuId ?? $Item.userPrincipalName ?? [guid]::NewGuid().ToString()
            $RowKey = $RowKeyControlRegex.Replace($RowKeyPathRegex.Replace("$Type-$ItemId", '_'), '')
            if ($SeenInBatch.Add($RowKey)) {
                $Batch.Add(@{
                        PartitionKey = $TenantFilter
                        RowKey       = $RowKey
                        # Depth 100, not 10: settings-catalog policies (e.g. macOS
                        # Platform SSO) nest deeper than 10 levels - a lower depth
                        # silently strips @odata.type/settingDefinitionId from deep
                        # children and every consumer sees a mangled object.
                        Data         = [string]($Item | ConvertTo-Json -Depth 100 -Compress)
                        Type         = $Type
                        RunId        = $RunId
                    })
                if ($Batch.Count -ge $BatchSize) {
                    $null = Add-CIPPAzDataTableEntity @Table -Entity $Batch.ToArray() -Force
                    $TotalProcessed += $Batch.Count
                    $Batch.Clear()
                    $SeenInBatch.Clear()
                }
            }
        }
    }

    end {
        if ($Batch.Count -gt 0) {
            $null = Add-CIPPAzDataTableEntity @Table -Entity $Batch.ToArray() -Force
            $TotalProcessed += $Batch.Count
        }

        # Clean up orphaned rows (entities that no longer exist in the new dataset).
        # Empty collections only clear existing data when the caller explicitly confirms
        # the response was authoritative by passing -ClearOnEmpty.
        if (-not $Count.IsPresent -and -not $Append.IsPresent -and ($TotalProcessed -gt 0 -or $ClearOnEmpty.IsPresent)) {
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}0'" -f $TenantFilter, $Type

            # The Timestamp predicate is NARROWING ONLY: it lets the service return candidate
            # orphans instead of every row of this type for the tenant, which at the end of a
            # tenant-wide cache write was a second full copy of the dataset materialised exactly
            # when the caller still held its first. The RunId check below is the delete
            # authority, so if this predicate were ever dropped, unsupported, or subtly wrong,
            # the candidate set merely changes size - rows this run wrote still cannot be
            # deleted, because they carry this run's id.
            #
            # -ClearOnEmpty must consider every row (the source authoritatively returned the
            # full - possibly empty - set), so it skips the narrowing.
            if (-not $ClearOnEmpty.IsPresent) {
                $Filter += " and Timestamp lt datetime'{0}'" -f $RunStartUtc.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
            }

            $Existing = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, ETag, OriginalEntityId, RunId
            if ($Existing) {
                $Orphans = foreach ($Row in @($Existing)) {
                    if ($Row.RowKey -eq "$Type-Count") { continue }

                    # Identity is the authority: a row written by this run always carries this
                    # run's id, no matter how long the run took, how the clocks drift, or what
                    # the query returned. Anything else - an earlier run's row, or a legacy row
                    # with no RunId at all - is an orphan by definition of an authoritative
                    # full-set write.
                    if ([string]$Row.RunId -ne $RunId) { $Row }
                }
                if ($Orphans) {
                    $null = Remove-CIPPAzDataTableEntity @Table -Entity @($Orphans) -Force
                }
            }
        }

        if ($Count.IsPresent -or $AddCount.IsPresent) {
            $NewCount = $TotalProcessed
            if ($Append.IsPresent) {
                $Filter = "PartitionKey eq '{0}' and RowKey eq '{1}-Count'" -f $TenantFilter, $Type
                $ExistingCount = Get-CIPPAzDataTableEntity @Table -Filter $Filter
                if ($ExistingCount.DataCount) { $NewCount += [int]$ExistingCount.DataCount }
            }
            $null = Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = $TenantFilter
                RowKey       = "$Type-Count"
                DataCount    = [int]$NewCount
                Type         = $Type
            } -Force
        }

        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Added $TotalProcessed items of type $Type" -sev Debug
    }
}
