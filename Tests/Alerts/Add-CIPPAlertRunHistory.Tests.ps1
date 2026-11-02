# Run history rows are partitioned by UTC day with a newest-first RowKey, and a completed run of an alert with a
# minimum interval also stamps the 'LastRun' marker the scheduler reads. A storage failure never fails the alert run.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($tablename) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPAlertRunHistory.ps1')
    $script:Task = [pscustomobject]@{ RowKey = 'task-1'; Name = 'Breach alert'; Command = 'Get-CIPPAlertBreachAlert' }
}

Describe 'Add-CIPPAlertRunHistory' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPTable { @{ Context = 'stub' } }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add($Entity) }
    }

    It 'writes a day-partitioned row that sorts newer runs first' {
        Add-CIPPAlertRunHistory -Task $script:Task -Tenant 'contoso.com' -TenantId 'cust-1' -Outcome 'Completed' -Counts @{ New = 2 } -StartedUtc ([datetime]'2026-10-23T10:00:00Z').ToUniversalTime()
        Add-CIPPAlertRunHistory -Task $script:Task -Tenant 'contoso.com' -TenantId 'cust-1' -Outcome 'Completed' -StartedUtc ([datetime]'2026-10-23T11:00:00Z').ToUniversalTime()

        $script:Writes.PartitionKey | Should -Be @('20261023', '20261023')
        [string]::CompareOrdinal($script:Writes[1].RowKey, $script:Writes[0].RowKey) | Should -BeLessThan 0
        ($script:Writes[0].Alert, $script:Writes[0].New, $script:Writes[0].Resolved) | Should -Be @('BreachAlert', 2, 0)
    }

    It 'stamps the LastRun marker only when asked, with the scheduled slot rather than the pickup time' {
        $Slot = ([datetime]'2026-10-23T02:00:00Z').ToUniversalTime()
        Add-CIPPAlertRunHistory -Task $script:Task -Tenant 'contoso.com' -TenantId 'cust-1' -Outcome 'Completed' -StartedUtc $Slot.AddMinutes(20) -ScheduledTime ([datetimeoffset]::new($Slot).ToUnixTimeSeconds()) -RecordCompletion
        $script:Writes.Count | Should -Be 2
        ($script:Writes[1].PartitionKey, $script:Writes[1].RowKey, $script:Writes[1].ScheduledTime) | Should -Be @('LastRun', 'task-1_cust-1', '1792720800')
        ($script:Writes[0].ExecutedTime, $script:Writes[0].ScheduledTime) | Should -Be @('1792722000', '1792720800')
    }

    It 'does not throw when storage fails' {
        Mock Add-CIPPAzDataTableEntity { throw 'table unavailable' }
        { Add-CIPPAlertRunHistory -Task $script:Task -Tenant 'contoso.com' -Outcome 'Skipped' 6>$null } | Should -Not -Throw
    }
}
