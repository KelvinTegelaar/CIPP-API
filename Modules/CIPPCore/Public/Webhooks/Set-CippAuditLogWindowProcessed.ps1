function Set-CippAuditLogWindowProcessed {
    <#
    .SYNOPSIS
        Mark one AuditLogCoverage window as Processed with a point write.
    .DESCRIPTION
        Replaces a "SearchId eq X" lookup. SearchId is not a key, so that scanned the tenant's
        ledger partition once per search plus once per Downloaded window in the sweep behind it.
        The batch item carries the window RowKey, so this addresses the row directly.
    .PARAMETER TenantFilter
        Tenant the window belongs to (the ledger PartitionKey).
    .PARAMETER WindowRowKey
        The AuditLogCoverage RowKey for the window.
    .PARAMETER MatchedCount
        Records that matched a rule in this window.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$WindowRowKey,
        [int]$MatchedCount = 0
    )

    if (-not $PSCmdlet.ShouldProcess($WindowRowKey, 'Mark audit log window Processed')) { return }

    $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
    try {
        Add-CIPPAzDataTableEntity @Ledger -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = $WindowRowKey
            State        = 'Processed'
            ProcessedUtc = (Get-Date).ToUniversalTime()
            MatchedCount = $MatchedCount
        } -OperationType UpsertMerge
        Write-Information "AuditLogV2: marked window $WindowRowKey Processed for $TenantFilter"
    } catch {
        # Not fatal: the records are already processed and deleted. The window stays in Processing
        # and the stale reclaim picks it up, which costs a re-read of an empty partition.
        Write-Information "AuditLogV2: could not mark window $WindowRowKey Processed for ${TenantFilter}: $($_.Exception.Message)"
    }
}
