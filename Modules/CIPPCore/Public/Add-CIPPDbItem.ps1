function Add-CIPPDbItem {
    <#
    .SYNOPSIS
        Add items to the CIPP Reporting database
    .FUNCTIONALITY
        Internal

    .PARAMETER ClearOnEmpty
        Authorizes removal of existing rows when InputObject is an authoritative empty
        collection and exact row-key cleanup for a non-empty authoritative collection.
        Callers must only use this after a successful source response.
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
        $SeenRowKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
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
                $null = $SeenRowKeys.Add($RowKey)
                $Batch.Add(@{
                        PartitionKey = $TenantFilter
                        RowKey       = $RowKey
                        Data         = [string]($Item | ConvertTo-Json -Depth 10 -Compress)
                        Type         = $Type
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
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, ETag, OriginalEntityId, Timestamp
            if ($Existing) {
                $Undated = 0
                $Orphans = foreach ($Row in @($Existing)) {
                    if ($Row.RowKey -eq "$Type-Count") { continue }

                    if ($ClearOnEmpty.IsPresent) {
                        if (-not $SeenRowKeys.Contains($Row.RowKey)) { $Row }
                        continue
                    }

                    $Stamp = $Row.Timestamp -as [datetimeoffset]
                    if ($null -eq $Stamp) { $Undated++; continue }

                    if ($Stamp -lt $RunStartUtc) { $Row }
                }
                if ($Undated -gt 0) {
                    Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -sev Warning -message "Skipped $Undated $Type row(s) with no readable Timestamp during orphan cleanup — not deleting without positive evidence"
                }
                if ($Orphans) {
                    $null = Remove-CIPPAzDataTableEntity @Table -Entity @($Orphans) -Force
                }
            }
        }

        if ($Count.IsPresent -or $AddCount.IsPresent) {
            $CntStart = $Stopwatch.ElapsedMilliseconds
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
            $CountMs = $Stopwatch.ElapsedMilliseconds - $CntStart
        }

        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Added $TotalProcessed items of type $Type" -sev Debug
    }
}
