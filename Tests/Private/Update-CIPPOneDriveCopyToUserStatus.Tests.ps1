# Pester tests for Update-CIPPOneDriveCopyToUserStatus: per-job polling, rate limit, rotation and state mapping.
# The table is faked in memory so successive status calls see what earlier ones stored.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Update-CIPPOneDriveCopyToUserStatus.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($Filter, $TableName) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force, $OperationType, $TableName) }
    function Update-CIPPAzDataTableEntity { param($Entity, [switch]$Force, $OperationType, $TableName) }
    function Get-CIPPSharePointLibraryCopyOperation { param($TenantFilter, $OperationId, $TableName) }
    function Get-CIPPSharePointCopyJobProgress { param($TenantFilter, $SourceSiteUrl, $CopyJobInfo) }
    function Update-CIPPSharePointLibraryCopyStatus { param($TenantFilter, $OperationId, $TableName) }

    . $FunctionPath
    # Partition keys: the real helper over a Get-Tenants that knows no tenant, so rows are keyed by the
    # lower-cased tenantFilter unless a test says otherwise.
    function Get-Tenants { param($TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPOneDriveCopyTenantKey.ps1')

    $script:OpId = '11111111-2222-3333-4444-555555555555'
    function New-Recipient([int]$Index, [string]$Upn, [string]$StartError, [int]$JobCount = 3) {
        [pscustomobject]@{ Index = $Index; UserPrincipalName = $Upn; FolderName = 'jane@contoso.com'; SubOperationId = "$($script:OpId)-r$Index"; JobCount = $JobCount; StartError = $StartError }
    }
    # Source totals default to what three jobs of New-Progress $true 2 add up to (6 files, 60 bytes).
    function Set-Operation([object[]]$Recipients, [int]$RootItemCount = 3, $Files = 6, $Bytes = 60, [bool]$VersionHistory = $false) {
        $script:Store = @{}
        $script:Store[$script:OpId] = [pscustomobject]@{
            PartitionKey = 'contoso.com'; RowKey = $script:OpId; Kind = 'Operation'; ETag = 'etag-initial'; LeaverUPN = 'jane@contoso.com'
            StartedBy = 'admin@partner.com'; StartedUtc = '2026-11-13T00:00:00Z'; RootItemCount = $RootItemCount; ExpectedBytes = $Bytes
            SourceFileCount = $Files; SourceBytes = $Bytes; IncludeVersionHistory = $VersionHistory
            Recipients = (ConvertTo-Json -InputObject @($Recipients) -Compress -Depth 4)
        }
    }
    # Progress per job: "<recipient>-<job>" -> object or scriptblock; default = still running.
    # By default a job has created one file of 10 bytes per object and expects as many objects as it has processed.
    function New-Progress([bool]$Complete, [int]$Objects = 1, [int]$Errors = 0, [string[]]$Messages = @(), $Files = $Objects, $Bytes = $Objects * 10, $Expected = $Objects) {
        [pscustomobject]@{ IsComplete = $Complete; JobState = if ($Complete) { 0 } else { 4 }; ObjectsProcessed = $Objects; TotalExpectedObjects = $Expected; FilesCreated = $Files; BytesProcessed = $Bytes; TotalErrors = $Errors; TotalWarnings = 0; ErrorMessages = $Messages; WarningMessages = @() }
    }
    function Invoke-Status([int]$Interval = 0, [int]$Max = 100) {
        Update-CIPPOneDriveCopyToUserStatus -TenantFilter 'contoso.com' -OperationId $script:OpId -MinimumIntervalSeconds $Interval -MaxJobsPerCheck $Max
    }
}

Describe 'Update-CIPPOneDriveCopyToUserStatus' {
    BeforeEach {
        Set-Operation @((New-Recipient 0 'bob@contoso.com'))
        $script:Progress = @{}
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -match "RowKey eq '([^']+)'") { $script:Store[$Matches[1]] }
            elseif ($Filter -match "RowKey ge '([^']+)' and RowKey lt '([^']+)'") {
                $Low = $Matches[1]; $High = $Matches[2]
                $script:Store.Values | Where-Object { [string]::CompareOrdinal($_.RowKey, $Low) -ge 0 -and [string]::CompareOrdinal($_.RowKey, $High) -lt 0 }
            }
        }
        Mock Add-CIPPAzDataTableEntity {
            foreach ($Item in @($Entity)) {
                $Existing = $script:Store[$Item.RowKey]
                if ($OperationType -eq 'UpsertMerge' -and $Existing) {
                    foreach ($Key in $Item.Keys) { $Existing | Add-Member -NotePropertyName $Key -NotePropertyValue $Item[$Key] -Force }
                    $Existing | Add-Member -NotePropertyName ETag -NotePropertyValue ([guid]::NewGuid().Guid) -Force
                } else {
                    $Row = [pscustomobject]$Item
                    $Row | Add-Member -NotePropertyName ETag -NotePropertyValue ([guid]::NewGuid().Guid) -Force
                    $script:Store[$Item.RowKey] = $Row
                }
            }
        }
        Mock Update-CIPPAzDataTableEntity {
            # Fake If-Match: the update applies only when the entity carries the stored row's ETag.
            foreach ($Item in @($Entity)) {
                $Existing = $script:Store[$Item.RowKey]
                if (-not $Existing) { throw 'ResourceNotFound' }
                if ($Force -ne $true -and [string]$Item.ETag -ne [string]$Existing.ETag) { throw 'UpdateConditionNotSatisfied (412)' }
                foreach ($Prop in $Item.PSObject.Properties) { if ($Prop.Name -ne 'ETag') { $Existing | Add-Member -NotePropertyName $Prop.Name -NotePropertyValue $Prop.Value -Force } }
                $Existing | Add-Member -NotePropertyName ETag -NotePropertyValue ([guid]::NewGuid().Guid) -Force
            }
        }
        Mock Get-CIPPSharePointLibraryCopyOperation {
            $Index = [int]($OperationId -replace '.*-r', '')
            $Count = ($script:Store[$script:OpId].Recipients | ConvertFrom-Json | Where-Object Index -EQ $Index).JobCount
            [pscustomobject]@{ SourceSiteUrl = 'https://contoso-my.sharepoint.com/personal/jane'; CopyJobInfos = @(0..($Count - 1) | ForEach-Object { [pscustomobject]@{ JobId = "$Index-$_" } }) }
        }
        Mock Get-CIPPSharePointCopyJobProgress {
            $Value = $script:Progress[$CopyJobInfo.JobId]
            if ($Value -is [scriptblock]) { & $Value } elseif ($Value) { $Value } else { New-Progress $false 0 }
        }
        Mock Update-CIPPSharePointLibraryCopyStatus { throw 'the library copy status must not be used' }
    }

    It 'maps <Case> to <Expected>' -ForEach @(
        @{ Case = 'nothing processed yet'; Jobs = @{}; Expected = 'Queued'; Complete = $false }
        @{ Case = 'jobs running'; Jobs = @{ '0-0' = 'running' }; Expected = 'InProgress'; Complete = $false }
        @{ Case = 'a failed job while others still run'; Jobs = @{ '0-0' = 'errors' }; Expected = 'InProgress'; Complete = $false }
        @{ Case = 'every job done cleanly'; Jobs = @{ '0-0' = 'done'; '0-1' = 'done'; '0-2' = 'done' }; Expected = 'Completed'; Complete = $true }
        @{ Case = 'every job done, one with errors'; Jobs = @{ '0-0' = 'done'; '0-1' = 'errors'; '0-2' = 'done' }; Expected = 'Failed'; Complete = $true }
    ) {
        foreach ($Key in $Jobs.Keys) {
            $script:Progress[$Key] = switch ($Jobs[$Key]) {
                'running' { New-Progress $false 2 }
                'done' { New-Progress $true 2 }
                'errors' { New-Progress $true 1 1 @('File: access denied') }
            }
        }
        $Result = Invoke-Status
        $Result.Recipients[0].State | Should -Be $Expected
        $Result.Recipients[0].IsComplete | Should -Be $Complete
        $Result.State | Should -Be $Expected
        $Result.AllCompleted | Should -Be ($Expected -eq 'Completed')
        Should -Invoke Get-CIPPSharePointLibraryCopyOperation -ParameterFilter { $TableName -eq 'OneDriveCopyToUser' -and $OperationId -eq "$($script:OpId)-r0" }
    }

    It 'reports item count, bytes and errors per recipient' {
        $script:Progress['0-0'] = New-Progress $true 4
        $script:Progress['0-1'] = New-Progress $true 5 1 @('File: access denied')
        $script:Progress['0-2'] = New-Progress $true 1
        $Recipient = (Invoke-Status).Recipients[0]
        $Recipient.ItemsCopied | Should -Be 10
        $Recipient.BytesCopied | Should -Be 100
        $Recipient.ErrorCount | Should -Be 1
        $Recipient.Errors | Should -Be @('File: access denied')
        $Recipient.JobsComplete | Should -Be 3
    }

    It 'does not ask SharePoint again within the minimum interval, and returns the stored state' {
        $script:Progress['0-0'] = New-Progress $false 2
        $First = Invoke-Status -Interval 60
        $First.CheckedSharePoint | Should -BeTrue
        $First.JobsPolled | Should -Be 3
        Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 3 -Exactly

        $Second = Invoke-Status -Interval 60
        $Second.CheckedSharePoint | Should -BeFalse
        $Second.JobsPolled | Should -Be 0
        $Second.Recipients[0].State | Should -Be 'InProgress'
        $Second.Recipients[0].ObjectsProcessed | Should -Be 2
        Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 3 -Exactly
        Should -Invoke Get-CIPPSharePointLibraryCopyOperation -Times 1 -Exactly
    }

    Context 'ETag-claimed check' {
        It 'lets exactly one of two concurrent callers poll; the other returns the stored state' {
            $script:Progress['0-0'] = New-Progress $true 2
            # Both callers read the operation row before either claims it.
            $Snapshot = $script:Store[$script:OpId].PSObject.Copy()
            Mock Get-CIPPAzDataTableEntity { $Snapshot.PSObject.Copy() } -ParameterFilter { $Filter -match "RowKey eq '$($script:OpId)'" }

            $First = Invoke-Status 60
            $Second = Invoke-Status 60

            $First.CheckedSharePoint | Should -BeTrue
            $First.JobsPolled | Should -Be 3
            $Second.CheckedSharePoint | Should -BeFalse
            $Second.JobsPolled | Should -Be 0
            Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 3 -Exactly
            # The loser reports what the winner stored.
            $Second.Recipients[0].JobsComplete | Should -Be 1
            $Second.Recipients[0].State | Should -Be $First.Recipients[0].State
        }

        It 'never treats an ETag mismatch as a claim' {
            $script:Store[$script:OpId].ETag = 'someone-else-wrote-this'
            $Stale = $script:Store[$script:OpId].PSObject.Copy()
            $Stale.ETag = 'etag-initial'
            Mock Get-CIPPAzDataTableEntity { $Stale } -ParameterFilter { $Filter -match "RowKey eq '$($script:OpId)'" }
            $Result = Invoke-Status 60
            $Result.CheckedSharePoint | Should -BeFalse
            Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
            $script:Store[$script:OpId].PSObject.Properties.Name | Should -Not -Contain 'LastCheckedUnix'
        }

        It 'does not poll when the operation row has no ETag' {
            $script:Store[$script:OpId].PSObject.Properties.Remove('ETag')
            $Result = Invoke-Status 60
            $Result.CheckedSharePoint | Should -BeFalse
            Should -Invoke Update-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 0 -Exactly
        }

        It 'does not poll when the claim write fails for another reason' {
            Mock Update-CIPPAzDataTableEntity { throw 'Storage 503' }
            (Invoke-Status 60).CheckedSharePoint | Should -BeFalse
            Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 0 -Exactly
        }

        It 'claims with an If-Match update (no -Force) of the operation row only' {
            $null = Invoke-Status 60
            Should -Invoke Update-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.RowKey -eq $script:OpId -and $Entity.ETag -eq 'etag-initial' -and $Entity.LastCheckedUnix -gt 0 -and -not $Force
            }
        }

        It 'a lost claim only delays: the next call after the window polls' {
            $Snapshot = $script:Store[$script:OpId].PSObject.Copy()
            Mock Get-CIPPAzDataTableEntity { $Snapshot.PSObject.Copy() } -ParameterFilter { $Filter -match "RowKey eq '$($script:OpId)'" }
            $null = Invoke-Status 60
            (Invoke-Status 60).CheckedSharePoint | Should -BeFalse
            # The window passes; a fresh read of the row carries the winner's ETag.
            Mock Get-CIPPAzDataTableEntity { $Row = $script:Store[$script:OpId].PSObject.Copy(); $Row.LastCheckedUnix = 1; $Row } -ParameterFilter { $Filter -match "RowKey eq '$($script:OpId)'" }
            (Invoke-Status 60).CheckedSharePoint | Should -BeTrue
        }

        It 'stops starting polls once three quarters of the window has gone' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' -JobCount 3))
            $script:Progress['0-0'] = { Start-Sleep -Milliseconds 1700; New-Progress $false 1 }
            $Result = Invoke-Status 2
            $Result.JobsPolled | Should -Be 1
        }
    }

    It 'checks again once the interval has passed' {
        Invoke-Status -Interval 60 | Out-Null
        $script:Store[$script:OpId].LastCheckedUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 61
        (Invoke-Status -Interval 60).CheckedSharePoint | Should -BeTrue
        Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 6 -Exactly
    }

    It 'polls at most MaxJobsPerCheck jobs per check, rotating so every job is reached, and is only Completed once all are confirmed' {
        Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 5), (New-Recipient 1 'carol@contoso.com' $null 5)) -RootItemCount 5 -Files 5 -Bytes 50
        foreach ($r in 0..1) { foreach ($j in 0..4) { $script:Progress["$r-$j"] = New-Progress $true 1 } }

        $script:Seen = [System.Collections.Generic.List[string]]::new()
        Mock Get-CIPPSharePointCopyJobProgress { $script:Seen.Add($CopyJobInfo.JobId); $script:Progress[$CopyJobInfo.JobId] }

        $First = Invoke-Status -Max 4
        $First.JobsPolled | Should -Be 4
        $First.State | Should -Not -Be 'Completed'
        $First.AllCompleted | Should -BeFalse

        $Second = Invoke-Status -Max 4
        $Second.JobsPolled | Should -Be 4
        $Second.AllCompleted | Should -BeFalse

        $Third = Invoke-Status -Max 4
        $Third.JobsPolled | Should -Be 2
        $Third.State | Should -Be 'Completed'
        @($script:Seen | Sort-Object -Unique).Count | Should -Be 10
        $script:Seen.Count | Should -Be 10 -Because 'a finished job is never polled again'
    }

    It 'polls the least recently polled unfinished jobs first' {
        $script:Seen = [System.Collections.Generic.List[string]]::new()
        Mock Get-CIPPSharePointCopyJobProgress { $script:Seen.Add($CopyJobInfo.JobId); New-Progress $false 1 }
        Invoke-Status -Max 2 | Out-Null
        $script:Store["$($script:OpId)-js-0-0000"].LastPolledUnix = 1
        $script:Store["$($script:OpId)-js-0-0001"].LastPolledUnix = 5
        Invoke-Status -Max 2 | Out-Null
        $script:Seen | Should -Be @('0-0', '0-1', '0-2', '0-0')
    }

    It 'keeps a job unfinished through transient progress failures and fails it after five in a row' {
        Mock Get-CIPPSharePointCopyJobProgress { throw 'GetCopyJobProgress 503 https://contoso-my.sharepoint.com/x' }
        foreach ($i in 1..4) { (Invoke-Status).Recipients[0].IsComplete | Should -BeFalse }
        $Result = Invoke-Status
        $Result.Recipients[0].State | Should -Be 'Failed'
        $Result.Recipients[0].Errors[0] | Should -BeLike 'Progress could not be read 5 times in a row*'
        $Result.Recipients[0].Errors[0] | Should -Not -BeLike '*https://*'
    }

    It 'fails a job whose copy handle is missing' {
        Mock Get-CIPPSharePointLibraryCopyOperation { [pscustomobject]@{ SourceSiteUrl = 'https://contoso-my.sharepoint.com/personal/jane'; CopyJobInfos = @([pscustomobject]@{ JobId = '0-0' }) } }
        $script:Progress['0-0'] = New-Progress $true 1
        $Result = Invoke-Status
        $Result.Recipients[0].State | Should -Be 'Failed'
        $Result.Recipients[0].Errors | Should -Contain 'The stored copy job could not be found.'
    }

    It 'aggregates <Case> to <Expected>' -ForEach @(
        @{ Case = 'one completed, one never started'; Jobs = @{ 0 = 'done' }; StartErrors = @{ 1 = 'Copy failed to start: x' }; Expected = 'Failed'; IsComplete = $true }
        @{ Case = 'one never started, one still running'; Jobs = @{ 0 = 'running' }; StartErrors = @{ 1 = 'Copy failed to start: x' }; Expected = 'InProgress'; IsComplete = $false }
        @{ Case = 'one failed with errors, one still queued'; Jobs = @{ 0 = 'errors' }; StartErrors = @{}; Expected = 'InProgress'; IsComplete = $false }
        @{ Case = 'all queued'; Jobs = @{}; StartErrors = @{}; Expected = 'Queued'; IsComplete = $false }
        @{ Case = 'one queued, one completed'; Jobs = @{ 1 = 'done' }; StartErrors = @{}; Expected = 'InProgress'; IsComplete = $false }
    ) {
        Set-Operation @((New-Recipient 0 'bob@contoso.com' $StartErrors[0]), (New-Recipient 1 'carol@contoso.com' $StartErrors[1]))
        foreach ($r in $Jobs.Keys) {
            foreach ($j in 0..2) {
                $script:Progress["$r-$j"] = switch ($Jobs[$r]) {
                    'done' { New-Progress $true 2 }
                    'running' { New-Progress $false 2 }
                    'errors' { New-Progress $true 1 1 @('x') }
                }
            }
        }
        $Result = Invoke-Status
        $Result.State | Should -Be $Expected
        $Result.IsComplete | Should -Be $IsComplete
        $Result.AllCompleted | Should -BeFalse
        @($Result.Recipients).Count | Should -Be 2
    }

    It 'reports a recipient that never started as Failed without polling it' {
        Set-Operation @((New-Recipient 0 'bob@contoso.com' 'Copy failed to start: Access denied'))
        $Result = Invoke-Status
        $Result.Recipients[0].State | Should -Be 'Failed'
        $Result.Recipients[0].Message | Should -Be 'Copy failed to start: Access denied'
        $Result.State | Should -Be 'Failed'
        Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 0 -Exactly
    }

    It 'is never Completed for an operation with no recipient records' {
        $script:Store[$script:OpId].Recipients = $null
        $Result = Invoke-Status
        $Result.AllCompleted | Should -BeFalse
        $Result.State | Should -Not -Be 'Completed'
    }

    It 'lets a missing per-recipient record surface as not found (so the licence gate keeps the licences)' {
        Mock Get-CIPPSharePointLibraryCopyOperation { $null }
        { Invoke-Status } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'refuses a row in the table that is not an operation' {
        $script:Store[$script:OpId].Kind = $null
        { Invoke-Status } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'only reads the operation in the requested tenant' {
        Update-CIPPOneDriveCopyToUserStatus -TenantFilter "o'brien.com" -OperationId $script:OpId -ErrorAction SilentlyContinue 2>$null | Out-Null
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -eq "PartitionKey eq 'o''brien.com' and RowKey eq '$($script:OpId)'" }
    }

    It 'throws ItemNotFoundException for an unknown operation' {
        $script:Store = @{}
        { Invoke-Status } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'throws ArgumentException for a malformed OperationId without querying storage' {
        { Update-CIPPOneDriveCopyToUserStatus -TenantFilter 'contoso.com' -OperationId "x' or PartitionKey ne '" } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'defaults to a 60 second interval and 100 jobs per check' {
        $Command = Get-Command Update-CIPPOneDriveCopyToUserStatus
        $Command.Parameters.Keys | Should -Contain 'MinimumIntervalSeconds'
        (Invoke-Status -Interval 60).CheckedSharePoint | Should -BeTrue
        (Update-CIPPOneDriveCopyToUserStatus -TenantFilter 'contoso.com' -OperationId $script:OpId).CheckedSharePoint | Should -BeFalse
    }
    Context 'licence gate safety (tester)' {
        BeforeEach {
            # Moves every stored timestamp back, as if this many seconds had passed before the next check.
            function Step-Clock([int]$Seconds = 60) {
                foreach ($Row in @($script:Store.Values)) {
                    if ($null -ne $Row.LastPolledUnix) { $Row.LastPolledUnix = [int64]$Row.LastPolledUnix - $Seconds }
                    if ($null -ne $Row.LastCheckedUnix) { $Row.LastCheckedUnix = [int64]$Row.LastCheckedUnix - $Seconds }
                }
            }
        }

        # LRU with ties broken by index is not perfectly even, but no unfinished job ever waits more
        # than ceil(unfinished / MaxJobsPerCheck) checks between two polls.
        It 'reaches every unfinished job within ceil(unfinished/cap) checks when none ever finishes (no starvation)' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 7), (New-Recipient 1 'carol@contoso.com' $null 7)) -RootItemCount 7
            $script:Polls = [System.Collections.Generic.List[object]]::new()
            $script:Check = 0
            Mock Get-CIPPSharePointCopyJobProgress { $script:Polls.Add([pscustomobject]@{ Job = $CopyJobInfo.JobId; Check = $script:Check }); New-Progress $false 1 }

            foreach ($Check in 1..30) {
                $script:Check = $Check
                $Result = Invoke-Status -Interval 60 -Max 3
                $Result.CheckedSharePoint | Should -BeTrue
                $Result.JobsPolled | Should -Be 3
                $Result.AllCompleted | Should -BeFalse
                Step-Clock
            }
            $Jobs = @($script:Polls | Group-Object Job)
            $Jobs.Count | Should -Be 14
            foreach ($Job in $Jobs) {
                $Checks = @(0) + @($Job.Group.Check) + @(31)
                for ($i = 1; $i -lt $Checks.Count; $i++) {
                    ($Checks[$i] - $Checks[$i - 1]) | Should -BeLessOrEqual 5 -Because "job $($Job.Name) must be polled at least every ceil(14/3) checks"
                }
            }
        }

        It 'keeps rotating to the remaining jobs as others finish' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 6)) -RootItemCount 6
            $script:Polls = [System.Collections.Generic.List[object]]::new()
            $script:Check = 0
            # Even jobs finish on their first poll, odd jobs never do.
            Mock Get-CIPPSharePointCopyJobProgress {
                $script:Polls.Add([pscustomobject]@{ Job = $CopyJobInfo.JobId; Check = $script:Check })
                New-Progress ([int]($CopyJobInfo.JobId -split '-')[1] % 2 -eq 0) 1
            }
            foreach ($Check in 1..12) { $script:Check = $Check; $Result = Invoke-Status -Interval 60 -Max 2; Step-Clock }
            foreach ($Even in '0-0', '0-2', '0-4') { @($script:Polls | Where-Object Job -EQ $Even).Count | Should -Be 1 }
            foreach ($Odd in '0-1', '0-3', '0-5') {
                $Checks = @($script:Polls | Where-Object Job -EQ $Odd | ForEach-Object Check)
                # after the first pass (3 checks), each of the 3 unfinished jobs is polled at least every ceil(3/2) = 2 checks
                @($Checks | Where-Object { $_ -gt 3 }).Count | Should -BeGreaterOrEqual 4
            }
            $Result.AllCompleted | Should -BeFalse
        }

        It 'keeps what a check already read when the check is cut short' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 12), (New-Recipient 1 'carol@contoso.com' $null 12)) -RootItemCount 12
            foreach ($j in 0..11) { $script:Progress["0-$j"] = New-Progress $false 1 1 @("File: error $j") }
            # The check dies when it reaches the second recipient (stands in for a timeout or worker recycle).
            Mock Get-CIPPSharePointLibraryCopyOperation { throw 'worker recycled' } -ParameterFilter { $OperationId -like '*-r1' }

            { Invoke-Status -Interval 60 -Max 100 } | Should -Throw '*worker recycled*'

            $Saved = @($script:Store.Values | Where-Object { $_.RowKey -like "$($script:OpId)-js-0-*" })
            $Saved.Count | Should -BeGreaterOrEqual 10 -Because 'job states are saved in batches of 10 while polling'
            @($Saved | ForEach-Object { $_.ErrorMessages | ConvertFrom-Json }) | Should -Contain 'File: error 0'
            @($Saved | Where-Object { [int64]$_.LastPolledUnix -gt 0 }).Count | Should -Be $Saved.Count
        }

        It 'returns the stored (unfinished) state inside the rate window even if SharePoint has since finished' {
            $script:Progress['0-0'] = New-Progress $false 1
            Invoke-Status -Interval 60 | Out-Null
            foreach ($j in 0..2) { $script:Progress["0-$j"] = New-Progress $true 1 }
            $Result = Invoke-Status -Interval 60
            $Result.CheckedSharePoint | Should -BeFalse
            $Result.AllCompleted | Should -BeFalse
        }

        It 'is never Completed while one job keeps failing to report, and fails it after five checks' {
            foreach ($j in 0..1) { $script:Progress["0-$j"] = New-Progress $true 1 }
            $script:Progress['0-2'] = { throw 'GetCopyJobProgress 429' }
            foreach ($Check in 1..4) {
                $Result = Invoke-Status
                $Result.AllCompleted | Should -BeFalse
                $Result.IsComplete | Should -BeFalse
            }
            $Result = Invoke-Status
            $Result.State | Should -Be 'Failed'
            $Result.AllCompleted | Should -BeFalse
        }

        It 'only gives up on five failures in a row, not five in total' {
            $script:Progress['0-0'] = { throw 'GetCopyJobProgress 503' }
            foreach ($Check in 1..4) { Invoke-Status | Out-Null }
            $script:Progress['0-0'] = New-Progress $false 1
            Invoke-Status | Out-Null
            $script:Progress['0-0'] = { throw 'GetCopyJobProgress 503' }
            foreach ($Check in 1..4) { (Invoke-Status).Recipients[0].IsComplete | Should -BeFalse }
        }

        It 'never completes a recipient from stored rows of another operation' {
            $Other = '99999999-2222-3333-4444-555555555555'
            foreach ($j in 0..2) {
                $script:Store["$Other-js-0-000$j"] = [pscustomobject]@{ RowKey = "$Other-js-0-000$j"; RecipientIndex = 0; JobIndex = $j; IsFinal = $true; Failed = $false; ObjectsProcessed = 1 }
            }
            (Invoke-Status -Interval 60).AllCompleted | Should -BeFalse
            # and inside the rate window, with nothing polled, still not complete
            (Invoke-Status -Interval 60).AllCompleted | Should -BeFalse
        }
    }

    Context 'strict completion (OneDrive copy only)' {
        It 'completes the live run: 7 root items bundled into 4 jobs whose totals match the source' {
            # Real readings after completion: SharePoint put 7 root items into 4 jobs; the source held
            # 7 files, 2,068,394 bytes (current versions). A KeepBoth rename counts as a created file.
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 4)) -RootItemCount 7 -Files 7 -Bytes 2068394
            $script:Progress['0-0'] = New-Progress $true 10 -Files 2 -Bytes 29 -Expected 10
            $script:Progress['0-1'] = New-Progress $true 4 -Files 2 -Bytes 12 -Expected 4
            $script:Progress['0-2'] = New-Progress $true 4 -Files 2 -Bytes 2068334 -Expected 4
            $script:Progress['0-3'] = New-Progress $true 2 -Files 1 -Bytes 19 -Expected 2
            $Result = Invoke-Status
            $Result.Recipients[0].State | Should -Be 'Completed'
            $Result.Recipients[0].JobsTotal | Should -Be 4
            $Result.Recipients[0].ItemsCopied | Should -Be 7
            $Result.Recipients[0].BytesCopied | Should -Be 2068394
            $Result.AllCompleted | Should -BeTrue
            $Result.SourceFileCount | Should -Be 7
            $Result.SourceBytes | Should -Be 2068394
        }

        It 'fails the live run when a file is missing, even with matching bytes elsewhere' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 4)) -RootItemCount 7 -Files 7 -Bytes 2068394
            $script:Progress['0-0'] = New-Progress $true 10 -Files 2 -Bytes 29 -Expected 10
            $script:Progress['0-1'] = New-Progress $true 4 -Files 2 -Bytes 12 -Expected 4
            $script:Progress['0-2'] = New-Progress $true 4 -Files 2 -Bytes 2068334 -Expected 4
            $script:Progress['0-3'] = New-Progress $true 2 -Files 0 -Bytes 19 -Expected 2
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Failed'
            $Recipient.IsComplete | Should -BeTrue
            $Recipient.Message | Should -Be 'Copy finished, but copied 6 of 7 files.'
            $Recipient.Errors | Should -Contain 'Copy finished, but copied 6 of 7 files.'
            $Recipient.ErrorCount | Should -Be 1
        }

        It 'completes the live run with a warning when <Case>' -ForEach @(
            @{ Case = 'bytes fall short with every file copied'; Files = 1; Bytes = 18; Warning = 'Copied 2068393 bytes; 2068394 bytes were counted when the copy started*' }
            @{ Case = 'bytes exceed the source without version history'; Files = 1; Bytes = 20; Warning = 'Copied 2068395 bytes; 2068394 bytes were counted when the copy started*' }
            @{ Case = 'more files than the source were copied'; Files = 2; Bytes = 19; Warning = 'Copied 8 files, more than the 7 counted when the copy started*' }
        ) {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 4)) -RootItemCount 7 -Files 7 -Bytes 2068394
            $script:Progress['0-0'] = New-Progress $true 10 -Files 2 -Bytes 29 -Expected 10
            $script:Progress['0-1'] = New-Progress $true 4 -Files 2 -Bytes 12 -Expected 4
            $script:Progress['0-2'] = New-Progress $true 4 -Files 2 -Bytes 2068334 -Expected 4
            $script:Progress['0-3'] = New-Progress $true 2 -Files $Files -Bytes $Bytes -Expected 2
            $Result = Invoke-Status
            $Recipient = $Result.Recipients[0]
            $Recipient.State | Should -Be 'Completed'
            $Recipient.IsComplete | Should -BeTrue
            $Recipient.ErrorCount | Should -Be 0
            $Recipient.Message | Should -BeLike 'Copy completed with warnings: *'
            @($Recipient.Warnings | Where-Object { $_ -like $Warning }).Count | Should -Be 1
            $Result.AllCompleted | Should -BeTrue
        }

        It 'never turns job errors into a warning, even when the totals match' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 1)) -RootItemCount 1 -Files 1 -Bytes 10
            $script:Progress['0-0'] = New-Progress $true 2 -Files 1 -Bytes 10 -Expected 2 -Errors 1 -Messages @('File: access denied')
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Failed'
            $Recipient.Message | Should -Not -BeLike '*warning*'
            $Recipient.Errors | Should -Contain 'File: access denied'
        }

        It 'with version history, completes on at least the current-version bytes and warns below them' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 1)) -RootItemCount 2 -Files 2 -Bytes 100 -VersionHistory $true
            $script:Progress['0-0'] = New-Progress $true 3 -Files 2 -Bytes 250
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Completed'
            $Recipient.Message | Should -Be 'Copy completed.'

            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 1)) -RootItemCount 2 -Files 2 -Bytes 100 -VersionHistory $true
            $script:Progress['0-0'] = New-Progress $true 3 -Files 2 -Bytes 99
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Completed'
            $Recipient.Message | Should -BeLike '*Copied 99 bytes with version history, less than the 100 bytes*'
        }

        It 'does not compare totals while jobs are still running' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 4)) -RootItemCount 7 -Files 7 -Bytes 2068394
            $script:Progress['0-0'] = New-Progress $true 10 -Files 2 -Bytes 29 -Expected 10
            $Result = Invoke-Status
            $Result.Recipients[0].State | Should -Be 'InProgress'
            $Result.Recipients[0].Message | Should -Be 'Copy in progress (1 of 4 copy jobs done).'
        }

        It 'completes a source holding only an empty folder (2 objects, no files, no bytes)' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 1)) -RootItemCount 1 -Files 0 -Bytes 0
            $script:Progress['0-0'] = New-Progress $true 2 -Files 0 -Bytes 0 -Expected 2
            (Invoke-Status).Recipients[0].State | Should -Be 'Completed'
        }

        It 'completes a source holding only a 0-byte file (2 objects, 1 file, no bytes)' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 1)) -RootItemCount 1 -Files 1 -Bytes 0
            $script:Progress['0-0'] = New-Progress $true 2 -Files 1 -Bytes 0 -Expected 2
            (Invoke-Status).Recipients[0].State | Should -Be 'Completed'
        }

        It 'fails a recipient with <Case>, without polling it' -ForEach @(
            @{ Case = 'no jobs'; Jobs = 0; Message = '*0 copy job(s) for 3 root item(s)*' }
            @{ Case = 'more jobs than root items'; Jobs = 4; Message = '*4 copy job(s) for 3 root item(s)*' }
        ) {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null $Jobs)) -RootItemCount 3
            $Result = Invoke-Status
            $Result.Recipients[0].State | Should -Be 'Failed'
            $Result.Recipients[0].Message | Should -BeLike $Message
            $Result.AllCompleted | Should -BeFalse
            Should -Invoke Get-CIPPSharePointCopyJobProgress -Times 0 -Exactly
        }

        It 'never completes an operation started without source totals' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com'))
            $script:Store[$script:OpId].PSObject.Properties.Remove('SourceFileCount')
            $script:Store[$script:OpId].PSObject.Properties.Remove('SourceBytes')
            foreach ($j in 0..2) { $script:Progress["0-$j"] = New-Progress $true 2 }
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Failed'
            $Recipient.Message | Should -BeLike '*was not recorded when the copy started*'
        }

        It 'fails a job that finishes having processed fewer objects than it expected' {
            $script:Progress['0-0'] = New-Progress $true 2 -Expected 3
            $script:Progress['0-1'] = New-Progress $true 2
            $script:Progress['0-2'] = New-Progress $true 2
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Failed'
            $Recipient.Errors | Should -Contain 'The copy job finished having processed 2 of 3 objects.'
        }

        It 'fails a job that finishes without reporting how many objects it expected' {
            $script:Progress['0-0'] = New-Progress $true 2 -Expected $null
            $script:Progress['0-1'] = New-Progress $true 2
            $script:Progress['0-2'] = New-Progress $true 2
            (Invoke-Status).Recipients[0].State | Should -Be 'Failed'
        }

        It 'keeps the highest file, byte and object counts seen per job across readings' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com' $null 1)) -RootItemCount 1 -Files 4 -Bytes 40
            $script:Progress['0-0'] = New-Progress $false 4
            Invoke-Status | Out-Null
            # A later, final reading whose log batch no longer carries the progress lines.
            $script:Progress['0-0'] = New-Progress $true 0 -Expected 4
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.ItemsCopied | Should -Be 4
            $Recipient.BytesCopied | Should -Be 40
            $Recipient.State | Should -Be 'Completed'
        }

        It 'keeps the highest error count and every error message across checks' {
            $script:Progress['0-0'] = New-Progress $false 1 2 @('File: locked')
            Invoke-Status | Out-Null
            $script:Progress['0-0'] = New-Progress $false 2 0 @('File: too long')
            Invoke-Status | Out-Null
            $script:Progress['0-0'] = New-Progress $true 3 1 @()
            $script:Progress['0-1'] = New-Progress $true 1
            $script:Progress['0-2'] = New-Progress $true 1
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Failed'
            $Recipient.ErrorCount | Should -Be 2
            $Recipient.Errors | Should -Be @('File: locked', 'File: too long')
        }

        It 'fails a job that finishes with nothing processed' {
            $script:Progress['0-0'] = New-Progress $true 0
            $script:Progress['0-1'] = New-Progress $true 1
            $script:Progress['0-2'] = New-Progress $true 1
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Failed'
            $Recipient.Errors | Should -Contain 'The copy job finished without copying anything.'
        }

        It 'fails a job that finishes with nothing processed, even when the totals would add up' {
            Set-Operation @((New-Recipient 0 'bob@contoso.com')) -Files 4 -Bytes 40
            $script:Progress['0-0'] = New-Progress $true 0 -Expected 0
            $script:Progress['0-1'] = New-Progress $true 2
            $script:Progress['0-2'] = New-Progress $true 2
            $Recipient = (Invoke-Status).Recipients[0]
            $Recipient.State | Should -Be 'Failed'
            $Recipient.Errors | Should -Contain 'The copy job finished without copying anything.'
        }

        It 'does not finish a job cleanly when SharePoint did not confirm it (JobState unknown), and fails it after five such checks' {
            # What the shared parser returns when GetCopyJobProgress fails but the queue log shows progress.
            $script:Progress['0-0'] = [pscustomobject]@{ IsComplete = $true; JobState = -1; ObjectsProcessed = 5; TotalExpectedObjects = 9; FilesCreated = 5; BytesProcessed = 50; TotalErrors = 0; TotalWarnings = 0; ErrorMessages = @(); WarningMessages = @() }
            $script:Progress['0-1'] = New-Progress $true 2
            $script:Progress['0-2'] = New-Progress $true 2
            for ($i = 1; $i -le 4; $i++) {
                $Result = Invoke-Status
                $Result.State | Should -Be 'InProgress'
                $Result.Recipients[0].JobsComplete | Should -Be 2
            }
            $Result = Invoke-Status
            $Result.State | Should -Be 'Failed'
            $Result.Recipients[0].Errors | Should -Contain 'SharePoint did not confirm the copy job finished after 5 checks in a row.'
        }

        It 'completes once SharePoint confirms the job after an unconfirmed reading' {
            $script:Progress['0-0'] = [pscustomobject]@{ IsComplete = $true; JobState = -1; ObjectsProcessed = 1; TotalExpectedObjects = 2; FilesCreated = 1; BytesProcessed = 10; TotalErrors = 0; TotalWarnings = 0; ErrorMessages = @(); WarningMessages = @() }
            $script:Progress['0-1'] = New-Progress $true 2
            $script:Progress['0-2'] = New-Progress $true 2
            (Invoke-Status).State | Should -Be 'InProgress'
            $script:Progress['0-0'] = New-Progress $true 2
            (Invoke-Status).State | Should -Be 'Completed'
        }

        It 'still fails a job on an unconfirmed reading that reports errors' {
            $script:Progress['0-0'] = [pscustomobject]@{ IsComplete = $true; JobState = -1; ObjectsProcessed = 1; TotalExpectedObjects = 2; FilesCreated = 0; BytesProcessed = 0; TotalErrors = 1; TotalWarnings = 0; ErrorMessages = @('File: access denied'); WarningMessages = @() }
            $script:Progress['0-1'] = New-Progress $true 2
            $script:Progress['0-2'] = New-Progress $true 2
            (Invoke-Status).State | Should -Be 'Failed'
        }

        It 'does not let a later reading lower the counts' {
            $script:Progress['0-0'] = New-Progress $false 5
            Invoke-Status | Out-Null
            $script:Progress['0-0'] = New-Progress $false 2
            (Invoke-Status).Recipients[0].ItemsCopied | Should -Be 5
        }
    }
    Context 'partition key' {
        BeforeEach {
            $script:CustomerId = 'c0ffee00-1111-2222-3333-444444444444'
            Mock Get-Tenants { [pscustomobject]@{ customerId = $script:CustomerId; defaultDomainName = 'contoso.com' } }
            # The table honours PartitionKey here, so a lookup under the wrong key finds nothing.
            Mock Get-CIPPAzDataTableEntity {
                $Pk = if ($Filter -match "PartitionKey eq '([^']+)'") { $Matches[1] }
                $Found = if ($Filter -match "RowKey eq '([^']+)'") { $script:Store[$Matches[1]] }
                elseif ($Filter -match "RowKey ge '([^']+)' and RowKey lt '([^']+)'") {
                    $Low = $Matches[1]; $High = $Matches[2]
                    $script:Store.Values | Where-Object { [string]::CompareOrdinal($_.RowKey, $Low) -ge 0 -and [string]::CompareOrdinal($_.RowKey, $High) -lt 0 }
                }
                @($Found) | Where-Object { $_ -and [string]$_.PartitionKey -ceq $Pk }
            }
            $script:Progress['0-0'] = New-Progress $true 2
            $script:Progress['0-1'] = New-Progress $true 2
            $script:Progress['0-2'] = New-Progress $true 2
        }

        It 'finds a copy keyed by the customerId when polled with <Case>' -ForEach @(
            @{ Case = 'the domain'; Poll = 'contoso.com' }
            @{ Case = 'the domain in another case'; Poll = 'CONTOSO.com' }
            @{ Case = 'the tenant id'; Poll = 'c0ffee00-1111-2222-3333-444444444444' }
            @{ Case = 'the tenant id in upper case'; Poll = 'C0FFEE00-1111-2222-3333-444444444444' }
        ) {
            $script:Store[$script:OpId].PartitionKey = $script:CustomerId
            $Result = Update-CIPPOneDriveCopyToUserStatus -TenantFilter $Poll -OperationId $script:OpId -MinimumIntervalSeconds 0
            $Result.State | Should -Be 'Completed'
            Should -Invoke Get-CIPPSharePointLibraryCopyOperation -ParameterFilter { $TenantFilter -eq $script:CustomerId }
            # Job states are stored next to the operation; SharePoint is still asked with the caller's tenant.
            @($script:Store.Values | Where-Object { $_.RowKey -like "$($script:OpId)-js-*" } | ForEach-Object { $_.PartitionKey } | Sort-Object -Unique) | Should -Be @($script:CustomerId)
            Should -Invoke Get-CIPPSharePointCopyJobProgress -ParameterFilter { $TenantFilter -eq $Poll }
        }

        It 'does not find a copy of another tenant' {
            $script:Store[$script:OpId].PartitionKey = 'dddddddd-1111-2222-3333-444444444444'
            { Update-CIPPOneDriveCopyToUserStatus -TenantFilter 'contoso.com' -OperationId $script:OpId } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
        }
    }
}
