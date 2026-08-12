# Pester tests for Push-StoreMailboxPermissions
#
# The fan-in of the mailbox permission orchestrator: $Item.Results already holds the whole
# tenant's permission set, so rows are streamed straight into Add-CIPPDbItem rather than
# collected into intermediate lists (this job was one of two that took a production instance
# to 3.8GB). These tests lock the streaming write, the one-invocation-per-type rule that its
# orphan cleanup depends on, and the guard that keeps a rowless run from stamping a fresh
# -Count row of 0 over a cache it did not clear.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-StoreMailboxPermissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-StoreMailboxPermissions.ps1 under Modules/' }

    # Minimal stubs so Mock has commands to replace during tests.
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Add-CIPPDbItem {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$TenantFilter,
            [Parameter(Mandatory)][string]$Type,
            [Parameter(Mandatory, ValueFromPipeline)][AllowNull()][AllowEmptyCollection()]$InputObject,
            [switch]$Count,
            [switch]$AddCount,
            [switch]$Append
        )
    }

    . $FunctionPath

    function New-WorkItem {
        param($Results)
        @{
            Parameters = @{ TenantFilter = 'contoso.onmicrosoft.com' }
            Results    = $Results
        }
    }
}

Describe 'Push-StoreMailboxPermissions' {
    BeforeEach {
        $script:Rows = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPDbItem -MockWith { $script:Rows.Add(@{ Type = $Type; Row = $InputObject }) }
    }

    It 'streams mailbox, recipient and send-on-behalf rows into one MailboxPermissions pipeline' {
        $Item = New-WorkItem -Results @(
            @{
                'Get-MailboxPermission'   = @(@{ Identity = 'shared1'; User = 'a@x.com' }, @{ Identity = 'shared2'; User = 'b@x.com' })
                'Get-RecipientPermission' = @(@{ Identity = 'shared1'; Trustee = 'c@x.com' })
                'Get-Mailbox'             = @(@{ Identity = 'shared1'; GrantSendOnBehalfTo = 'd@x.com' })
            }
        )

        Push-StoreMailboxPermissions -Item $Item

        # Pester runs the mock body once per pipeline item: 4 single rows means the writer
        # was fed a stream, not a materialised list.
        $MailboxRows = @($script:Rows | Where-Object { $_.Type -eq 'MailboxPermissions' })
        $MailboxRows.Count | Should -Be 4
        $MailboxRows | ForEach-Object { @($_.Row).Count | Should -Be 1 }

        Should -Invoke Add-CIPPDbItem -Times 4 -Exactly -ParameterFilter {
            $AddCount.IsPresent -and $Type -eq 'MailboxPermissions' -and $TenantFilter -eq 'contoso.onmicrosoft.com'
        }
    }

    It 'streams calendar rows into a separate CalendarPermissions pipeline' {
        $Item = New-WorkItem -Results @(
            @{
                'Get-MailboxPermission'       = @(@{ Identity = 'shared1'; User = 'a@x.com' })
                'Get-MailboxFolderPermission' = @(@{ Identity = 'shared1:\Calendar'; User = 'b@x.com' }, @{ Identity = 'shared2:\Calendar'; User = 'c@x.com' })
            }
        )

        Push-StoreMailboxPermissions -Item $Item

        @($script:Rows | Where-Object { $_.Type -eq 'CalendarPermissions' }).Count | Should -Be 2
        Should -Invoke Add-CIPPDbItem -Times 2 -Exactly -ParameterFilter { $Type -eq 'CalendarPermissions' }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'MailboxPermissions' }
    }

    It 'unwraps a batch result shaped as [hashtable, status message]' {
        $Item = New-WorkItem -Results @(
            , @(@{ 'Get-MailboxPermission' = @(@{ Identity = 'shared1'; User = 'a@x.com' }) }, 'Batch completed')
        )

        Push-StoreMailboxPermissions -Item $Item

        @($script:Rows | Where-Object { $_.Type -eq 'MailboxPermissions' }).Count | Should -Be 1
    }

    It 'never invokes a writer for a type with no rows, so no -Count row is stamped' {
        # Every batch failed: strings instead of cmdlet-keyed hashtables. Add-CIPPDbItem's
        # end block writes the -Count row whenever -AddCount is present, so invoking it with
        # an empty stream would stamp a fresh count of 0 without clearing the data rows, and
        # the freshness gates that read count rows would treat the stale cache as current.
        $Item = New-WorkItem -Results @('error: batch 1 failed', 'error: batch 2 failed')

        Push-StoreMailboxPermissions -Item $Item

        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $message -eq 'No mailbox permissions found to cache'
        }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $message -eq 'No calendar permissions found to cache'
        }
    }

    It 'still writes the type that has rows when the other has none' {
        $Item = New-WorkItem -Results @(
            @{ 'Get-MailboxPermission' = @(@{ Identity = 'shared1'; User = 'a@x.com' }) }
        )

        Push-StoreMailboxPermissions -Item $Item

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'MailboxPermissions' }
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $Type -eq 'CalendarPermissions' }
    }

    It 'logs the cached totals per type' {
        $Item = New-WorkItem -Results @(
            @{
                'Get-MailboxPermission'       = @(@{ Identity = 'shared1'; User = 'a@x.com' }, @{ Identity = 'shared2'; User = 'b@x.com' })
                'Get-MailboxFolderPermission' = @(@{ Identity = 'shared1:\Calendar'; User = 'c@x.com' })
            }
        )

        Push-StoreMailboxPermissions -Item $Item

        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $message -eq 'Cached 2 mailbox permission records'
        }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $message -eq 'Cached 1 calendar permission records'
        }
    }
}
