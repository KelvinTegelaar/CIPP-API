function Add-CIPPDbItem {
    <#
    .SYNOPSIS
        Add items to the CIPP Reporting database
    .FUNCTIONALITY
        Internal
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
        [switch]$Append
    )

    begin {
        $Table = Get-CippTable -tablename 'CippReportingDB'
        $Batch = [System.Collections.Generic.List[hashtable]]::new()
        $NewRowKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $TotalProcessed = 0

        if ($TenantFilter -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
            try {
                $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter -IncludeErrors | Select-Object -First 1).defaultDomainName
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
            $RowKey = "$Type-$ItemId" -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', ''
            if ($NewRowKeys.Add($RowKey)) {
                $Batch.Add(@{
                        PartitionKey = $TenantFilter
                        RowKey       = $RowKey
                        Data         = [string]($Item | ConvertTo-Json -Depth 10 -Compress)
                        Type         = $Type
                    })
                if ($Batch.Count -ge 500) {
                    $null = Add-CIPPAzDataTableEntity @Table -Entity $Batch.ToArray() -Force
                    $TotalProcessed += $Batch.Count
                    $Batch.Clear()
                }
            }
        }
    }

    end {
        if ($Batch.Count -gt 0) {
            $null = Add-CIPPAzDataTableEntity @Table -Entity $Batch.ToArray() -Force
            $TotalProcessed += $Batch.Count
        }

        # Clean up orphaned rows (entities that no longer exist in the new dataset)
        if (-not $Count.IsPresent -and -not $Append.IsPresent -and $TotalProcessed -gt 0) {
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}0'" -f $TenantFilter, $Type
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, ETag, OriginalEntityId
            if ($Existing) {
                $Orphans = foreach ($Row in @($Existing)) {
                    if ($Row.RowKey -eq "$Type-Count") { continue }
                    $ParentKey = $Row.OriginalEntityId ?? $Row.RowKey
                    if (-not $NewRowKeys.Contains($ParentKey)) {
                        $Row
                    }
                }
                if ($Orphans) {
                    $null = Remove-AzDataTableEntity @Table -Entity @($Orphans) -Force
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
            } -Force
            $CountMs = $Stopwatch.ElapsedMilliseconds - $CntStart
        }

        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Added $TotalProcessed items of type $Type" -sev Debug
    }
}
