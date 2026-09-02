# Pester tests for Push-GetCalendarPermissionsBatch
#
# Phase 1 caches each mailbox's calendar folder name forever; Phase 2 reads permissions from
# it. Get-MailboxFolderStatistics returns EVERY calendar folder flattened under one
# OperationGuid, so picking the wrong row is silent and permanent - it cached holiday
# calendars for over half a tenant, and those mailboxes then cached no permissions at all.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-GetCalendarPermissionsBatch.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-GetCalendarPermissionsBatch.ps1 under Modules/' }

    # Minimal stubs so Mock has commands to replace during tests.
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox, $Anchor, $NoAuthCheck, $Select, $ReturnWithCommand) }

    . $FunctionPath

    function New-WorkItem {
        param($Mailboxes = @('user1@contoso.com'))
        [PSCustomObject]@{
            TenantFilter = 'contoso.onmicrosoft.com'
            Mailboxes    = $Mailboxes
            BatchNumber  = 1
            TotalBatches = 1
        }
    }

    function New-FolderStat {
        param($UPN, $Name, $FolderType)
        [PSCustomObject]@{ Name = $Name; FolderType = $FolderType; OperationGuid = $UPN }
    }
}

Describe 'Push-GetCalendarPermissionsBatch' {
    BeforeEach {
        $script:CacheEntries = @()
        $script:FolderStats = @()
        $script:PermResults = @()
        $script:Written = [System.Collections.Generic.List[object]]::new()
        $script:ExoCalls = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'CalendarFolderCache' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:CacheEntries }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { foreach ($e in @($Entity)) { $script:Written.Add($e) } }
        Mock -CommandName New-ExoBulkRequest -MockWith {
            $Name = @($cmdletArray)[0].CmdletInput.CmdletName
            $script:ExoCalls.Add([PSCustomObject]@{ Cmdlet = $Name; Select = $Select; Array = @($cmdletArray) })
            if ($Name -eq 'Get-MailboxFolderStatistics') { $script:FolderStats } else { $script:PermResults }
        }
    }

    It 'caches the root calendar even when a subfolder is the last folder returned' {
        # The exact ordering that produced the bug: the root arrives first and a localised
        # holiday calendar arrives last, so last-wins cached the holiday calendar.
        $script:FolderStats = @(
            New-FolderStat -UPN 'user1@contoso.com' -Name 'Calendar' -FolderType 'Calendar'
            New-FolderStat -UPN 'user1@contoso.com' -Name 'Helligdage i Danmark' -FolderType 'User Created'
            New-FolderStat -UPN 'user1@contoso.com' -Name 'Birthdays' -FolderType 'Birthday'
        )

        Push-GetCalendarPermissionsBatch -Item (New-WorkItem)

        $script:Written.Count | Should -Be 1
        $script:Written[0].FolderName | Should -Be 'Calendar'
        $script:Written[0].FolderType | Should -Be 'Calendar'
        $script:Written[0].RowKey | Should -Be 'user1@contoso.com'

        # ...and Phase 2 must then ask for that folder, not the holiday calendar.
        $Phase2 = @($script:ExoCalls | Where-Object { $_.Cmdlet -eq 'Get-MailboxFolderPermission' })
        $Phase2.Count | Should -Be 1
        $Phase2[0].Array[0].CmdletInput.Parameters.Identity | Should -Be 'user1@contoso.com:\Calendar'
    }

    It 'skips a mailbox with no root calendar rather than caching a guess' {
        $script:FolderStats = @(
            New-FolderStat -UPN 'user1@contoso.com' -Name 'United States holidays' -FolderType 'User Created'
        )

        Push-GetCalendarPermissionsBatch -Item (New-WorkItem)

        # Nothing cached, and no permission request built - a wrong name here would stick forever.
        $script:Written.Count | Should -Be 0
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        @($script:ExoCalls | Where-Object { $_.Cmdlet -eq 'Get-MailboxFolderPermission' }).Count | Should -Be 0
    }

    It 'treats a cache entry with no FolderType as a miss so a poisoned cache self-heals' {
        # Rows written before the fix carry a folder name but no FolderType, and the name alone
        # cannot say whether it is the root or a subfolder.
        $script:CacheEntries = @(
            [PSCustomObject]@{ PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'user1@contoso.com'; FolderName = 'Helligdage i Danmark' }
        )
        $script:FolderStats = @(
            New-FolderStat -UPN 'user1@contoso.com' -Name 'Calendar' -FolderType 'Calendar'
        )

        Push-GetCalendarPermissionsBatch -Item (New-WorkItem)

        @($script:ExoCalls | Where-Object { $_.Cmdlet -eq 'Get-MailboxFolderStatistics' }).Count | Should -Be 1
        $script:Written[0].FolderName | Should -Be 'Calendar'
    }

    It 'trusts a cache entry stamped as a root calendar and skips discovery' {
        $script:CacheEntries = @(
            [PSCustomObject]@{ PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'user1@contoso.com'; FolderName = 'Kalender'; FolderType = 'Calendar' }
        )

        Push-GetCalendarPermissionsBatch -Item (New-WorkItem)

        @($script:ExoCalls | Where-Object { $_.Cmdlet -eq 'Get-MailboxFolderStatistics' }).Count | Should -Be 0
        $Phase2 = @($script:ExoCalls | Where-Object { $_.Cmdlet -eq 'Get-MailboxFolderPermission' })
        $Phase2[0].Array[0].CmdletInput.Parameters.Identity | Should -Be 'user1@contoso.com:\Kalender'
    }

    It 'returns the permissions it read under the Get-MailboxFolderPermission key' {
        $script:CacheEntries = @(
            [PSCustomObject]@{ PartitionKey = 'contoso.onmicrosoft.com'; RowKey = 'user1@contoso.com'; FolderName = 'Calendar'; FolderType = 'Calendar' }
        )
        $script:PermResults = @(
            [PSCustomObject]@{ Identity = 'user1@contoso.com:\Calendar'; User = 'Default'; AccessRights = @('Reviewer'); FolderName = 'Calendar'; OperationGuid = 'user1@contoso.com' }
        )

        $Result = Push-GetCalendarPermissionsBatch -Item (New-WorkItem)

        @($Result['Get-MailboxFolderPermission']).Count | Should -Be 1
        @($Result['Get-MailboxFolderPermission'])[0].User | Should -Be 'Default'
    }
}
