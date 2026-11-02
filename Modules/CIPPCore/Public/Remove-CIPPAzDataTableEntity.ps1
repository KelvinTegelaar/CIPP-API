function Remove-CIPPAzDataTableEntity {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Removes entities from an Azure Table, including any part rows they were split into.
    .DESCRIPTION
    Thin wrapper around Remove-AzDataTableLargeEntity (AzBobbyTables >= 3.6.2), which
    also deletes the part rows of entities that were split for size, so removing a
    split entity leaves no orphaned rows behind.

    Kept as a wrapper for consistency with the other CIPP table helpers and to
    default MaxRetries to 3 for throttled requests.

    On TableNotFound, invalidates the CreateTable cache, recreates the table, and
    retries once so a stale CIPPEnsuredTables entry cannot permanently break deletes.
    #>
    [CmdletBinding()]
    param(
        $Context,
        $Entity,
        [switch]$Force,
        [int]$MaxRetries = 3
    )

    $Parameters = @{} + $PSBoundParameters
    $Parameters['MaxRetries'] = $MaxRetries
    $null = $Parameters.Remove('ErrorAction')

    try {
        Remove-AzDataTableLargeEntity @Parameters -ErrorAction Stop
    } catch {
        if ($script:CIPPRepairingTable -or -not (Test-CIPPTableNotFound $_)) {
            throw
        }
        $script:CIPPRepairingTable = $true
        try {
            Repair-CIPPTable -Context $Context
            Remove-AzDataTableLargeEntity @Parameters -ErrorAction Stop
        } finally {
            $script:CIPPRepairingTable = $false
        }
    }
}
