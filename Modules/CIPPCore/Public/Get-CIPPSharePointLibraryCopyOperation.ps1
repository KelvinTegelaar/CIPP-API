function Get-CIPPSharePointLibraryCopyOperation {
    <#
    .SYNOPSIS
        Loads a SharePointLibraryCopy operation row and reassembles chunked CopyJobInfo handles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$OperationId
    )

    $Table = Get-CIPPTable -TableName 'SharePointLibraryCopy'
    $SafeTenant = $TenantFilter -replace "'", "''"
    $SafeOp = $OperationId -replace "'", "''"
    $Primary = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeOp'") | Select-Object -First 1
    if (-not $Primary) {
        return $null
    }

    $ChunkRows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and startswith(RowKey, '$SafeOp`_')") |
        Sort-Object RowKey

    $HandlesParts = [System.Collections.Generic.List[string]]::new()
    if ($Primary.CopyJobInfos) { [void]$HandlesParts.Add([string]$Primary.CopyJobInfos) }
    foreach ($Chunk in $ChunkRows) {
        if ($Chunk.CopyJobInfos) { [void]$HandlesParts.Add([string]$Chunk.CopyJobInfos) }
    }

    $HandlesJson = -join $HandlesParts
    $CopyJobInfos = @()
    if (-not [string]::IsNullOrWhiteSpace($HandlesJson)) {
        $CopyJobInfos = @($HandlesJson | ConvertFrom-Json)
    }

    $HandleStates = @()
    if ($Primary.HandleStates) {
        $HandleStates = @($Primary.HandleStates | ConvertFrom-Json)
    }

    [PSCustomObject]@{
        PartitionKey      = $Primary.PartitionKey
        RowKey            = $Primary.RowKey
        OperationId       = $OperationId
        SourceSiteUrl     = $Primary.SourceSiteUrl
        SourceSiteName    = $Primary.SourceSiteName
        SourceLibraryName = $Primary.SourceLibraryName
        DestSiteName      = $Primary.DestSiteName
        DestLibraryName   = $Primary.DestLibraryName
        StartedBy         = $Primary.StartedBy
        Status            = $Primary.Status
        JobHandleCount    = [int]$Primary.JobHandleCount
        Expiry            = $Primary.Expiry
        CopyJobInfos      = @($CopyJobInfos)
        HandleStates      = @($HandleStates)
        SanitizedSnapshot = if ($Primary.SanitizedSnapshot) { $Primary.SanitizedSnapshot | ConvertFrom-Json } else { $null }
    }
}
