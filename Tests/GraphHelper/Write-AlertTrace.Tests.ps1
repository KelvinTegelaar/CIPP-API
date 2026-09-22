# Pester tests for Write-AlertTrace, the per-item alert lifecycle reconciler.
#
# Each alert run hands over everything it found (possibly nothing). Items are hashed and
# compared with the AlertLifecycle rows for that cmdlet and tenant: unknown items become
# Open and are returned for notification, known items are refreshed silently, absent
# items are resolved, resolved items that come back are reopened and returned again, and
# snoozed items are tracked but never returned. -Append never resolves by absence.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Helper = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper'

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $TableName, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($Context, $TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $TableName, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Get-CIPPActiveAlertSnoozes { param($CmdletName, $TenantFilter) }

    . (Join-Path $Helper 'Get-AlertContentHash.ps1')
    . (Join-Path $Helper 'Get-CIPPAlertLifecycleKey.ps1')
    . (Join-Path $Helper 'Write-AlertTrace.ps1')

    function New-StoredRow {
        param($Message, $Status = 'Open', $ReopenCount = '0', $ResolvedAt = '', $LastSeen = '2026-09-20T10:00:00.0000000Z')
        $Hash = Get-AlertContentHash -AlertItem @{ Message = $Message }
        $Keys = Get-CIPPAlertLifecycleKey -CmdletName 'Get-CIPPAlertSomething' -TenantFilter 'contoso.onmicrosoft.com' -ContentHash $Hash.ContentHash
        [pscustomobject]@{
            PartitionKey    = $Keys.PartitionKey
            RowKey          = $Keys.RowKey
            CmdletName      = 'Get-CIPPAlertSomething'
            Tenant          = 'contoso.onmicrosoft.com'
            ContentHash     = $Hash.ContentHash
            ContentPreview  = $Hash.ContentPreview
            AlertItem       = (ConvertTo-Json -InputObject @{ Message = $Message } -Compress)
            AlertComment    = ''
            Status          = $Status
            FirstSeen       = '2026-09-18T10:00:00.0000000Z'
            LastSeen        = $LastSeen
            LastChecked     = $LastSeen
            ResolvedAt      = $ResolvedAt
            ReopenCount     = $ReopenCount
            AcknowledgedBy  = ''
            AcknowledgedAt  = ''
            AcknowledgeNote = ''
            SnoozeUntil     = ''
            SnoozedBy       = ''
            SnoozeRowKey    = ''
            ETag            = 'W/"1"'
            Timestamp       = [datetimeoffset]::UtcNow
        }
    }

    function Get-WrittenRow {
        param($Message)
        $Hash = (Get-AlertContentHash -AlertItem @{ Message = $Message }).ContentHash
        $script:Writes | Where-Object { $_.ContentHash -eq $Hash } | Select-Object -Last 1
    }
}

Describe 'Write-AlertTrace' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @()
        $script:LastRun = @()
        $script:Snoozes = @{}

        Mock Get-CIPPTable { @{ TableName = $tablename } }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        Mock Get-CIPPActiveAlertSnoozes { $script:Snoozes }
        Mock Get-CIPPAzDataTableEntity {
            if ($TableName -eq 'AlertLifecycle') { return $script:Existing }
            if ($TableName -eq 'AlertLastRun') { return $script:LastRun }
        }
        Mock Add-CIPPAzDataTableEntity {
            foreach ($Row in @($Entity)) { $script:Writes.Add($Row) }
        }
        Mock Remove-CIPPAzDataTableEntity { $script:Removed.Add($Entity) }
    }

    It 'stores unknown items as Open and returns them for notification' {
        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @(
            [pscustomobject]@{ Message = 'first' }
            [pscustomobject]@{ Message = 'second' }
        )

        @($Result).Count | Should -Be 2
        @($Result).Message | Should -Be @('first', 'second')
        $script:Writes.Count | Should -Be 2
        (Get-WrittenRow -Message 'first').Status | Should -Be 'Open'
        (Get-WrittenRow -Message 'first').ReopenCount | Should -Be '0'
        (Get-WrittenRow -Message 'first').FirstSeen | Should -Not -BeNullOrEmpty
    }

    It 'refreshes known items without returning them' {
        $script:Existing = @(New-StoredRow -Message 'first')

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @([pscustomobject]@{ Message = 'first' })

        $Result | Should -BeNullOrEmpty
        $Written = Get-WrittenRow -Message 'first'
        $Written.Status | Should -Be 'Open'
        $Written.FirstSeen | Should -Be '2026-09-18T10:00:00.0000000Z'
        $Written.LastSeen | Should -Not -Be '2026-09-20T10:00:00.0000000Z'
    }

    It 'keeps an acknowledged item acknowledged while it persists' {
        $script:Existing = @(New-StoredRow -Message 'first' -Status 'Acknowledged')

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @([pscustomobject]@{ Message = 'first' })

        $Result | Should -BeNullOrEmpty
        (Get-WrittenRow -Message 'first').Status | Should -Be 'Acknowledged'
    }

    It 'resolves items missing from the run and returns nothing for an empty run' {
        $script:Existing = @(
            (New-StoredRow -Message 'first'),
            (New-StoredRow -Message 'second' -Status 'Acknowledged')
        )

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data $null

        $Result | Should -BeNullOrEmpty
        $script:Writes.Count | Should -Be 2
        (Get-WrittenRow -Message 'first').Status | Should -Be 'Resolved'
        (Get-WrittenRow -Message 'first').ResolvedAt | Should -Not -BeNullOrEmpty
        (Get-WrittenRow -Message 'second').Status | Should -Be 'Resolved'
        # The resolved rows keep every column so the full-row upsert loses nothing.
        (Get-WrittenRow -Message 'first').AlertItem | Should -Not -BeNullOrEmpty
        (Get-WrittenRow -Message 'first').Keys | Should -Not -Contain 'ETag'
    }

    It 'reopens a resolved item, bumps the reopen count and returns it again' {
        $script:Existing = @(New-StoredRow -Message 'first' -Status 'Resolved' -ReopenCount '1' -ResolvedAt '2026-09-21T10:00:00.0000000Z')

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @([pscustomobject]@{ Message = 'first' })

        @($Result).Count | Should -Be 1
        $Written = Get-WrittenRow -Message 'first'
        $Written.Status | Should -Be 'Open'
        $Written.ReopenCount | Should -Be '2'
        $Written.ResolvedAt | Should -Be ''
        $Written.FirstSeen | Should -Not -Be '2026-09-18T10:00:00.0000000Z'
    }

    It 'tracks a snoozed item as Snoozed without returning it' {
        $Hash = (Get-AlertContentHash -AlertItem @{ Message = 'first' }).ContentHash
        $script:Snoozes = @{ $Hash = [pscustomobject]@{ SnoozeUntil = '-1'; SnoozedBy = 'ops@contoso.com'; RowKey = 'contoso.onmicrosoft.com-hash' } }

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @([pscustomobject]@{ Message = 'first' })

        $Result | Should -BeNullOrEmpty
        $Written = Get-WrittenRow -Message 'first'
        $Written.Status | Should -Be 'Snoozed'
        $Written.SnoozedBy | Should -Be 'ops@contoso.com'
        $Written.SnoozeRowKey | Should -Be 'contoso.onmicrosoft.com-hash'
    }

    It 'fires again when a snooze has lapsed but the condition persists' {
        $script:Existing = @(New-StoredRow -Message 'first' -Status 'Snoozed')

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @([pscustomobject]@{ Message = 'first' })

        @($Result).Count | Should -Be 1
        (Get-WrittenRow -Message 'first').Status | Should -Be 'Open'
    }

    It 'does not resolve by absence in append mode, but does retire stale rows' {
        $script:Existing = @(
            (New-StoredRow -Message 'recent' -LastSeen ([datetime]::UtcNow.AddDays(-2).ToString('o'))),
            (New-StoredRow -Message 'stale' -LastSeen ([datetime]::UtcNow.AddDays(-45).ToString('o')))
        )

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @([pscustomobject]@{ Message = 'event' }) -Append

        @($Result).Count | Should -Be 1
        Get-WrittenRow -Message 'recent' | Should -BeNullOrEmpty
        (Get-WrittenRow -Message 'stale').Status | Should -Be 'Resolved'
    }

    It 'purges resolved rows older than the retention window' {
        $script:Existing = @(
            (New-StoredRow -Message 'old' -Status 'Resolved' -ResolvedAt ([datetime]::UtcNow.AddDays(-120).ToString('o'))),
            (New-StoredRow -Message 'fresh' -Status 'Resolved' -ResolvedAt ([datetime]::UtcNow.AddDays(-5).ToString('o')))
        )

        $null = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data $null

        $script:Removed.Count | Should -Be 1
        $script:Removed[0].RowKey | Should -Be (New-StoredRow -Message 'old').RowKey
        $script:Writes.Count | Should -Be 0
    }

    It 'seeds from the last AlertLastRun row so known items are not announced as new' {
        $script:LastRun = @(
            [pscustomobject]@{
                PartitionKey = '20260920'
                RowKey       = 'contoso.onmicrosoft.com-Get-CIPPAlertSomething'
                LogData      = (ConvertTo-Json -InputObject @(@{ Message = 'first' }) -Compress)
                AlertComment = ''
            }
        )

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @(
            [pscustomobject]@{ Message = 'first' }
            [pscustomobject]@{ Message = 'second' }
        )

        @($Result).Count | Should -Be 1
        @($Result)[0].Message | Should -Be 'second'
        (Get-WrittenRow -Message 'first').FirstSeen | Should -BeLike '2026-09-20*'
        (Get-WrittenRow -Message 'first').Status | Should -Be 'Open'
    }

    It 'ignores duplicate items within one run' {
        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertSomething' -tenantFilter 'contoso.onmicrosoft.com' -data @(
            [pscustomobject]@{ Message = 'first' }
            [pscustomobject]@{ Message = 'first' }
        )

        @($Result).Count | Should -Be 1
        $script:Writes.Count | Should -Be 1
    }
}
