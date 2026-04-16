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
        $TotalProcessed = 0

        if ($TenantFilter -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
            try {
                $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter -IncludeErrors | Select-Object -First 1).defaultDomainName
            } catch {}
        }

        if (-not $Count.IsPresent -and -not $Append.IsPresent) {
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}0'" -f $TenantFilter, $Type
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey, ETag
            if ($Existing) {
                $null = Remove-AzDataTableEntity @Table -Entity $Existing -Force
            }
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
            $Batch.Add(@{
                    PartitionKey = $TenantFilter
                    RowKey       = ("$Type-$ItemId" -replace '[/\\#?]', '_' -replace '[\u0000-\u001F\u007F-\u009F]', '')
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

    end {
        if ($Batch.Count -gt 0) {
            $null = Add-CIPPAzDataTableEntity @Table -Entity $Batch.ToArray() -Force
            $TotalProcessed += $Batch.Count
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
            } -Force
        }

        Write-LogMessage -API 'CIPPDbItem' -tenant $TenantFilter -message "Added $TotalProcessed items of type $Type" -sev Debug
    }
}
