# Pester tests for the "Copy OneDrive to user(s)" option in Invoke-CIPPOffboardingJob:
# - off: the batch is exactly what it was before the option existed
# - on: the copy step runs before licence removal, and licence removal waits for the copy

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $JobPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    $ValidatorPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPOffboardingRequest.ps1'

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Filter, $TableName) }
    function Update-AzDataTableEntity { param($Entity, [switch]$Force, $TableName) }

    . $HtmlPath
    . $JobPath
    . $ValidatorPath

    function Get-Batch($Options) {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]$Options)
        @($script:CapturedInput.Batch)
    }
}

Describe 'Invoke-CIPPOffboardingJob OneDrive copy' {
    BeforeEach {
        $script:CapturedInput = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-Information -MockWith { }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'aaaaaaaa-1111-2222-3333-444444444444'; displayName = 'Pat Lee'; onPremisesSyncEnabled = $false; onPremisesImmutableId = $null }
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { $script:CapturedInput = $InputObject; 'orch-1' }
    }

    It 'leaves the batch unchanged when the option is <Case>' -ForEach @(
        @{ Case = 'absent'; Extra = @{} }
        @{ Case = 'empty'; Extra = @{ OneDriveCopyTo = @() } }
        @{ Case = 'null'; Extra = @{ OneDriveCopyTo = $null } }
    ) {
        $Options = @{ RemoveLicenses = $true; DisableSignIn = $true; OnedriveAccess = @(@{ value = 'helper-id-1' }) } + $Extra
        $Batch = Get-Batch $Options
        @($Batch | ForEach-Object { $_.Cmdlet }) | Should -Be @('Set-CIPPSignInState', 'Set-CIPPSharePointPerms', 'Remove-CIPPLicense')
        ($Batch | Where-Object Cmdlet -EQ 'Remove-CIPPLicense').Title | Should -Be 'Remove licenses'
        ($Batch | Where-Object Cmdlet -EQ 'Remove-CIPPLicense').Parameters.Schedule | Should -BeTrue
    }

    It 'copies before removing licences, and removes them through the copy gate' {
        $Batch = Get-Batch @{ RemoveLicenses = $true; DisableSignIn = $true; OneDriveCopyTo = @(@{ label = 'Bob'; value = 'bob-id' }, 'carol@contoso.com') }
        $Cmdlets = @($Batch | ForEach-Object { $_.Cmdlet })

        $Cmdlets | Should -Not -Contain 'Remove-CIPPLicense'
        $Cmdlets.IndexOf('Invoke-CIPPOffboardingOneDriveCopy') | Should -BeLessThan $Cmdlets.IndexOf('Remove-CIPPLicenseAfterOneDriveCopy')
        $script:CapturedInput.Sequential | Should -BeTrue

        $Copy = $Batch | Where-Object Cmdlet -EQ 'Invoke-CIPPOffboardingOneDriveCopy'
        $Copy.Title | Should -Be 'Copy OneDrive to user(s)'
        $Copy.Parameters.Username | Should -Be 'pat@contoso.com'
        $Copy.Parameters.TenantFilter | Should -Be 'contoso.com'
        @($Copy.Parameters.Recipients).Count | Should -Be 2

        $Gate = $Batch | Where-Object Cmdlet -EQ 'Remove-CIPPLicenseAfterOneDriveCopy'
        $Gate.Parameters.userid | Should -Be 'aaaaaaaa-1111-2222-3333-444444444444'
        # Both steps carry the same operation id, so the gate waits for exactly this run's copy.
        $Copy.Parameters.OperationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        $Gate.Parameters.CopyOperationId | Should -Be $Copy.Parameters.OperationId
        $Gate.Parameters.ContainsKey('CopyStartedAfter') | Should -BeFalse
    }

    It 'copies without touching licences when Remove licenses is off' {
        $Cmdlets = @(Get-Batch @{ DisableSignIn = $true; OneDriveCopyTo = @('bob@contoso.com') } | ForEach-Object { $_.Cmdlet })
        $Cmdlets | Should -Be @('Set-CIPPSignInState', 'Invoke-CIPPOffboardingOneDriveCopy')
    }

    It 'skips the copy when the user is being deleted, like every other non-delete step' {
        $Cmdlets = @(Get-Batch @{ DeleteUser = $true; OneDriveCopyTo = @('bob@contoso.com') } | ForEach-Object { $_.Cmdlet })
        $Cmdlets | Should -Be @('Remove-CIPPUser')
    }

    It 'the validator accepts the copy as the only selected action' {
        function Test-CIPPHtmlIsEmpty { param($Html) $true }
        $Result = Test-CIPPOffboardingRequest -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; user = @(@{ value = 'pat@contoso.com' }); OneDriveCopyTo = @(@{ value = 'bob-id' }); DisableSignIn = $true })
        $Result.IsValid | Should -BeTrue
    }
    It 'runs the copy after Disable sign in' {
        $Cmdlets = @(Get-Batch @{ RemoveLicenses = $true; DisableSignIn = $true; RevokeSessions = $true; OneDriveCopyTo = @('bob@contoso.com') } | ForEach-Object { $_.Cmdlet })
        $Cmdlets.IndexOf('Set-CIPPSignInState') | Should -BeLessThan $Cmdlets.IndexOf('Invoke-CIPPOffboardingOneDriveCopy')
        $Cmdlets.IndexOf('Invoke-CIPPOffboardingOneDriveCopy') | Should -BeLessThan $Cmdlets.IndexOf('Remove-CIPPLicenseAfterOneDriveCopy')
    }

    It 'the validator refuses the copy without Disable sign in' -ForEach @(
        @{ Extra = @{} }
        @{ Extra = @{ DisableSignIn = $false } }
    ) {
        function Test-CIPPHtmlIsEmpty { param($Html) $true }
        $Body = @{ tenantFilter = 'contoso.com'; user = @(@{ value = 'pat@contoso.com' }); OneDriveCopyTo = @(@{ value = 'bob-id' }); RemoveLicenses = $true } + $Extra
        $Result = Test-CIPPOffboardingRequest -Body ([pscustomobject]$Body)
        $Result.IsValid | Should -BeFalse
        $Result.Errors | Should -BeLike "*OneDriveCopyLibrary') needs 'DisableSignIn'*"
    }

    It 'the validator refuses the copy together with Delete user' {
        function Test-CIPPHtmlIsEmpty { param($Html) $true }
        $Result = Test-CIPPOffboardingRequest -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; user = @(@{ value = 'pat@contoso.com' }); OneDriveCopyTo = @(@{ value = 'bob-id' }); DisableSignIn = $true; DeleteUser = $true })
        $Result.IsValid | Should -BeFalse
        @($Result.Errors).Count | Should -Be 1
        $Result.Errors | Should -BeLike "*OneDriveCopyLibrary') cannot be combined with 'DeleteUser'*"
    }

    It 'the validator still accepts Delete user without the copy' {
        function Test-CIPPHtmlIsEmpty { param($Html) $true }
        (Test-CIPPOffboardingRequest -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; user = @(@{ value = 'pat@contoso.com' }); DeleteUser = $true; OneDriveCopyTo = @() })).IsValid | Should -BeTrue
    }

    It 'the validator is unchanged when the copy is not selected' {
        function Test-CIPPHtmlIsEmpty { param($Html) $true }
        (Test-CIPPOffboardingRequest -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; user = @(@{ value = 'pat@contoso.com' }); RemoveLicenses = $true; OneDriveCopyTo = @() })).IsValid | Should -BeTrue
    }
    Context 'operation id kept with the offboarding run' {
        BeforeEach {
            # ScheduledTasks rows in memory: the offboarding's own task, as the scheduler stored it.
            $script:Tasks = @{
                'task-1' = [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; Command = 'Invoke-CIPPOffboardingJob'; Tenant = 'contoso.com'; Parameters = '{"Username":"pat@contoso.com"}' }
            }
            Mock Get-CIPPAzDataTableEntity { if ($Filter -match "RowKey eq '([^']+)'") { $script:Tasks[$Matches[1]] } }
            Mock Update-AzDataTableEntity {
                $Row = $script:Tasks[$Entity.RowKey]
                if (-not $Row) { throw 'ResourceNotFound' }
                $Row | Add-Member -NotePropertyName OneDriveCopyOperationId -NotePropertyValue $Entity.OneDriveCopyOperationId -Force
            }
            $script:Opts = [pscustomobject]@{ RemoveLicenses = $true; DisableSignIn = $true; OneDriveCopyTo = @('bob@contoso.com') }
            # Step indices in this batch: 0 Disable sign in, 1 Copy OneDrive, 2 Remove licences after the copy.
            function Invoke-Run([int[]]$Steps = @(), [string]$Owner, $TaskInfo = [pscustomobject]@{ RowKey = 'task-1' }) {
                $Params = @{ TenantFilter = 'contoso.com'; Username = 'pat@contoso.com'; Options = $script:Opts; TaskInfo = $TaskInfo; StepIndexes = $Steps }
                if ($Owner) { $Params.OffboardingTaskId = $Owner }
                $null = Invoke-CIPPOffboardingJob @Params
                @($script:CapturedInput.Batch)
            }
        }

        It 'records the copy id on the offboarding task when the whole run starts' {
            $Batch = @(Invoke-Run)
            $Id = ($Batch | Where-Object Cmdlet -EQ 'Invoke-CIPPOffboardingOneDriveCopy').Parameters.OperationId
            $Id | Should -Match '^[0-9a-f-]{36}$'
            ($Batch | Where-Object Cmdlet -EQ 'Remove-CIPPLicenseAfterOneDriveCopy').Parameters.CopyOperationId | Should -Be $Id
            $script:Tasks['task-1'].OneDriveCopyOperationId | Should -Be $Id
        }

        It 're-running only the licence step waits for the copy this offboarding started' {
            $First = @(Invoke-Run)
            $Id = ($First | Where-Object Cmdlet -EQ 'Invoke-CIPPOffboardingOneDriveCopy').Parameters.OperationId
            $Rerun = @(Invoke-Run -Steps @(2) -Owner 'task-1' -TaskInfo ([pscustomobject]@{ RowKey = 'rerun-task' }))
            @($Rerun).Count | Should -Be 1
            $Rerun[0].Cmdlet | Should -Be 'Remove-CIPPLicenseAfterOneDriveCopy'
            $Rerun[0].Parameters.CopyOperationId | Should -Be $Id
            Should -Invoke Update-AzDataTableEntity -Times 1 -Exactly
        }

        It 're-running the copy step starts a new copy under a new id, which a later licence-step re-run then waits for' {
            $First = @(Invoke-Run)
            $OldId = ($First | Where-Object Cmdlet -EQ 'Invoke-CIPPOffboardingOneDriveCopy').Parameters.OperationId
            $CopyRerun = @(Invoke-Run -Steps @(1) -Owner 'task-1' -TaskInfo ([pscustomobject]@{ RowKey = 'rerun-copy' }))
            $NewId = $CopyRerun[0].Parameters.OperationId
            $NewId | Should -Match '^[0-9a-f-]{36}$'
            $NewId | Should -Not -Be $OldId
            $script:Tasks['task-1'].OneDriveCopyOperationId | Should -Be $NewId
            # The re-run's own task is not where the id lives.
            Should -Invoke Update-AzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Entity.RowKey -eq 'rerun-copy' }

            $GateRerun = @(Invoke-Run -Steps @(2) -Owner 'task-1' -TaskInfo ([pscustomobject]@{ RowKey = 'rerun-gate' }))
            $GateRerun[0].Parameters.CopyOperationId | Should -Be $NewId
        }

        It 're-running copy and licence steps together gives both the same new id' {
            $null = @(Invoke-Run)
            $Rerun = @(Invoke-Run -Steps @(1, 2) -Owner 'task-1' -TaskInfo ([pscustomobject]@{ RowKey = 'rerun' }))
            $Rerun[0].Parameters.OperationId | Should -Be $Rerun[1].Parameters.CopyOperationId
            $script:Tasks['task-1'].OneDriveCopyOperationId | Should -Be $Rerun[0].Parameters.OperationId
        }

        It 'a full re-run of the task starts a new copy and records it' {
            $OldId = (Invoke-Run | Where-Object Cmdlet -EQ 'Invoke-CIPPOffboardingOneDriveCopy').Parameters.OperationId
            $NewId = (Invoke-Run | Where-Object Cmdlet -EQ 'Invoke-CIPPOffboardingOneDriveCopy').Parameters.OperationId
            $NewId | Should -Not -Be $OldId
            $script:Tasks['task-1'].OneDriveCopyOperationId | Should -Be $NewId
        }

        It 'gives the licence step no id (so it keeps the licences) when <Case>' -ForEach @(
            @{ Case = 'no copy was recorded'; Setup = { }; Owner = 'task-1' }
            @{ Case = 'the re-run does not name its offboarding'; Setup = { $script:Tasks['task-1'] | Add-Member OneDriveCopyOperationId '11111111-2222-3333-4444-555555555555' -Force }; Owner = $null }
            @{ Case = 'the named task is another user''s offboarding'; Setup = { $script:Tasks['task-1'] | Add-Member OneDriveCopyOperationId '11111111-2222-3333-4444-555555555555' -Force; $script:Tasks['task-1'].Parameters = '{"Username":"sam@contoso.com"}' }; Owner = 'task-1' }
            @{ Case = 'the named task is in another tenant'; Setup = { $script:Tasks['task-1'] | Add-Member OneDriveCopyOperationId '11111111-2222-3333-4444-555555555555' -Force; $script:Tasks['task-1'].Tenant = 'other.com' }; Owner = 'task-1' }
            @{ Case = 'the named task is not an offboarding'; Setup = { $script:Tasks['task-1'] | Add-Member OneDriveCopyOperationId '11111111-2222-3333-4444-555555555555' -Force; $script:Tasks['task-1'].Command = 'Invoke-Other' }; Owner = 'task-1' }
            @{ Case = 'the named task does not exist'; Setup = { }; Owner = 'missing-task' }
            @{ Case = 'the recorded id is not a GUID'; Setup = { $script:Tasks['task-1'] | Add-Member OneDriveCopyOperationId "x' or 1 eq 1" -Force }; Owner = 'task-1' }
        ) {
            . $Setup
            $Rerun = @(Invoke-Run -Steps @(2) -Owner $Owner -TaskInfo ([pscustomobject]@{ RowKey = 'rerun-gate' }))
            $Rerun[0].Cmdlet | Should -Be 'Remove-CIPPLicenseAfterOneDriveCopy'
            $Rerun[0].Parameters.CopyOperationId | Should -BeNullOrEmpty
            Should -Invoke Update-AzDataTableEntity -Times 0 -Exactly
        }

        It 'still starts the copy when the id cannot be recorded, and warns' {
            Mock Update-AzDataTableEntity { throw 'Storage 503' }
            $Batch = @(Invoke-Run)
            $Id = ($Batch | Where-Object Cmdlet -EQ 'Invoke-CIPPOffboardingOneDriveCopy').Parameters.OperationId
            $Id | Should -Match '^[0-9a-f-]{36}$'
            ($Batch | Where-Object Cmdlet -EQ 'Remove-CIPPLicenseAfterOneDriveCopy').Parameters.CopyOperationId | Should -Be $Id
            Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*Could not record OneDrive copy*' }
        }

        It 'reads and writes no task state when the option is off' {
            $script:Opts = [pscustomobject]@{ RemoveLicenses = $true; DisableSignIn = $true }
            $null = @(Invoke-Run)
            $null = @(Invoke-Run -Steps @(1) -Owner 'task-1')
            Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke Update-AzDataTableEntity -Times 0 -Exactly
        }
    }
}
