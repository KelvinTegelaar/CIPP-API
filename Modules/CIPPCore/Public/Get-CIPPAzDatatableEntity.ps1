function Get-CIPPAzDataTableEntity {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Gets entities from an Azure Table, reassembling entities that were split for size.
    .DESCRIPTION
    Thin wrapper around Get-AzDataTableLargeEntity (AzBobbyTables >= 3.6.2), which
    natively merges rows that were split across multiple properties or rows because
    they exceeded the table service size limits.

    Kept as a wrapper for backward compatibility with existing call sites and to
    default MaxRetries to 3 for throttled requests.
    #>
    [CmdletBinding()]
    param(
        $Context,
        $Filter,
        $Property,
        $First,
        $Skip,
        $Sort,
        [switch]$Count,
        [int]$MaxRetries = 3
    )

    $PSBoundParameters['MaxRetries'] = $MaxRetries
    Get-AzDataTableLargeEntity @PSBoundParameters
}
