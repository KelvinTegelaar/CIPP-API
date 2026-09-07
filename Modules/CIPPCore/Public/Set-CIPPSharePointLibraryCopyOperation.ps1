function Set-CIPPSharePointLibraryCopyOperation {
    <#
    .SYNOPSIS
        Persists a SharePointLibraryCopy operation, splitting large handle payloads across rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$OperationId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Entity
    )

    $Table = Get-CIPPTable -TableName 'SharePointLibraryCopy'

    $SafeTenant = $TenantFilter -replace "'", "''"
    $SafeOp = $OperationId -replace "'", "''"
    $PrimaryExisting = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeOp'") | Select-Object -First 1

    # Status-only updates must not rewrite CopyJobInfos (avoids delete/recreate races).
    $PreserveHandles = -not $Entity.ContainsKey('CopyJobInfos')
    if ($PreserveHandles -and $PrimaryExisting) {
        $MergeEntity = [ordered]@{
            PartitionKey = $TenantFilter
            RowKey       = $OperationId
        }
        foreach ($Key in $Entity.Keys) {
            $MergeEntity[$Key] = $Entity[$Key]
        }
        Add-CIPPAzDataTableEntity @Table -Entity ([hashtable]$MergeEntity) -OperationType UpsertMerge
        return
    }

    $ChunkRows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and startswith(RowKey, '$SafeOp`_')")
    $Existing = @($PrimaryExisting) + @($ChunkRows) | Where-Object { $_ }

    foreach ($Row in $Existing) {
        Remove-CIPPAzDataTableEntity @Table -Entity $Row -Force -ErrorAction SilentlyContinue
    }

    $Table.Force = $true

    $CopyJobInfos = $null
    if ($Entity.ContainsKey('CopyJobInfos')) {
        $CopyJobInfos = $Entity.CopyJobInfos
        $Entity.Remove('CopyJobInfos') | Out-Null
    }

    $BaseEntity = [ordered]@{
        PartitionKey = $TenantFilter
    }

    foreach ($Key in $Entity.Keys) {
        $BaseEntity[$Key] = $Entity[$Key]
    }

    if ($null -ne $CopyJobInfos) {
        $HandlesJson = ConvertTo-Json -InputObject @($CopyJobInfos) -Depth 8 -Compress
        $MaxChunk = 60000
        if ($HandlesJson.Length -le $MaxChunk) {
            $BaseEntity.CopyJobInfos = $HandlesJson
            $BaseEntity.RowKey = $OperationId
            Add-CIPPAzDataTableEntity @Table -Entity ([hashtable]$BaseEntity)
        } else {
            $ChunkIndex = 0
            for ($i = 0; $i -lt $HandlesJson.Length; $i += $MaxChunk) {
                $Len = [Math]::Min($MaxChunk, $HandlesJson.Length - $i)
                $Slice = $HandlesJson.Substring($i, $Len)
                if ($ChunkIndex -eq 0) {
                    $PrimaryEntity = [hashtable]$BaseEntity.Clone()
                    $PrimaryEntity.CopyJobInfos = $Slice
                    $PrimaryEntity.RowKey = $OperationId
                    if (-not $PrimaryEntity.Status) { $PrimaryEntity.Status = 'Queued' }
                    Add-CIPPAzDataTableEntity @Table -Entity $PrimaryEntity
                } else {
                    Add-CIPPAzDataTableEntity @Table -Entity @{
                        PartitionKey = $TenantFilter
                        RowKey       = "${OperationId}_$ChunkIndex"
                        CopyJobInfos = $Slice
                    }
                }
                $ChunkIndex++
            }
        }
    } else {
        $BaseEntity.RowKey = $OperationId
        Add-CIPPAzDataTableEntity @Table -Entity ([hashtable]$BaseEntity)
    }
}
