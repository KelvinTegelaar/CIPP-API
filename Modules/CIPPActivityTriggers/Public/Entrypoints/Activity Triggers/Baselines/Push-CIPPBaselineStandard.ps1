function Push-CIPPBaselineStandard {
    <#
    .SYNOPSIS
        Durable activity: run one baseline standard against one tenant.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    try {
        $null = Invoke-CIPPBaselineStandard -Item $Item.Item -Mode ($Item.Mode ?? 'run') -TriggeredBy ($Item.TriggeredBy ?? 'schedule') -Force:([bool]$Item.Force)
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $Item.Item.TenantFilter -message "Baseline activity failed for $($Item.Item.Standard): $($_.Exception.Message)" -Sev 'Error'
    } finally {
        if ($Item.QueueId) {
            $null = Update-CippQueueEntry -RowKey $Item.QueueId -Status 'Running' -Name $Item.QueueName
        }
    }
}
