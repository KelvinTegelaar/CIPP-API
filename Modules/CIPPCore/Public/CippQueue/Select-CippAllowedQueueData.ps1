function Select-CippAllowedQueueData {
    <#
    .SYNOPSIS
    Narrow queue status to what a tenant-restricted caller may see

    .DESCRIPTION
    Runs are shared between users: an AllTenants page load hands every caller the run already filling that
    cache, whoever started it. For a tenant-restricted caller, a run they did not start keeps only the tasks of
    their allowed tenants, with its counts taken from those tasks, and loses the name suffix, reference and link,
    which can name other tenants or count them. With -OwnOnly (a listing, not a lookup by id) only their own runs
    are returned. Every entry is marked Polled: restricted callers are not granted live run events, which carry
    the unfiltered run. Unrestricted callers get the data unchanged.

    Must live in CIPPCore: the scope slot is CIPPCore module-scoped (see Get-CippRequestContext).

    .PARAMETER Queues
    Queue entries as Get-CIPPQueueData returns them

    .PARAMETER User
    The caller (x-ms-client-principal-name), matched against the Owner recorded by New-CippQueueEntry

    .PARAMETER OwnOnly
    Drop runs the caller did not start instead of narrowing them

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $Queues,
        [string]$User,
        [switch]$OwnOnly
    )

    $Restricted = $script:CippAllowedTenantsStorage -and $null -ne $script:CippAllowedTenantsStorage.Value
    if (-not $Restricted) { return $Queues }

    $Owned = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($User) {
        $CippQueue = Get-CippTable -TableName CippQueue
        $SafeUser = ConvertTo-CIPPODataFilterValue -Value $User -Type String
        foreach ($Row in Get-CIPPAzDataTableEntity @CippQueue -Filter "PartitionKey eq 'CippQueue' and Owner eq '$SafeUser'" -Property PartitionKey, RowKey) {
            [void]$Owned.Add($Row.RowKey)
        }
    }
    $Allowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Tenant in Get-Tenants -IncludeErrors) {
        if ($Tenant.defaultDomainName) { [void]$Allowed.Add($Tenant.defaultDomainName) }
        if ($Tenant.customerId) { [void]$Allowed.Add($Tenant.customerId) }
    }

    foreach ($Queue in $Queues) {
        if (-not $Queue) { continue }
        # Craft names a queue's run '<Orchestrator>-<QueueId>'
        $QueueId = if ($Queue.QueueId) { $Queue.QueueId } elseif ($Queue.RowKey -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { $Matches[0] } else { $Queue.RowKey }
        if ($Owned.Contains($QueueId)) {
            $Queue | Select-Object *, @{ n = 'Polled'; e = { $true } } -ExcludeProperty Polled
            continue
        }
        if ($OwnOnly) { continue }

        $Tasks = @(@($Queue.Tasks).Where({ $_ -and $Allowed.Contains([string]$_.Name) }))
        $Failed = $Tasks.Where({ $_.Status -eq 'Failed' }).Count
        $Done = $Tasks.Where({ $_.Status -eq 'Completed' }).Count + $Failed
        $Running = $Tasks.Where({ $_.Status -eq 'Running' }).Count
        $Divisor = [Math]::Max($Tasks.Count, 1)
        [PSCustomObject]@{
            PartitionKey    = 'CippQueue'
            RowKey          = $QueueId
            QueueId         = $QueueId
            Name            = [string]$Queue.Name -replace '\s*\([^)]*\)\s*$', ''
            Link            = ''
            Reference       = ''
            TotalTasks      = $Tasks.Count
            CompletedTasks  = $Done
            RunningTasks    = $Running
            FailedTasks     = $Failed
            PercentComplete = [math]::Round($Done / $Divisor * 100, 1, [MidpointRounding]::AwayFromZero)
            PercentFailed   = [math]::Round($Failed / $Divisor * 100, 1, [MidpointRounding]::AwayFromZero)
            PercentRunning  = [math]::Round($Running / $Divisor * 100, 1, [MidpointRounding]::AwayFromZero)
            QueuedAhead     = $Queue.QueuedAhead
            RunsAhead       = $Queue.RunsAhead
            Tasks           = $Tasks
            Status          = $Queue.Status
            Timestamp       = $Queue.Timestamp
            Polled          = $true
        }
    }
}
