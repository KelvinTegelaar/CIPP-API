BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTimerFunctions.ps1')
}

Describe 'Get-CIPPTimerFunctions on Craft' {
    BeforeEach {
        $script:OriginalNG = $env:CIPPNG
        $script:OriginalRoot = $env:CIPPRootPath
        $env:CIPPNG = 'true'
        $env:CIPPRootPath = $BackendRoot
        $script:Fired = [DateTimeOffset]::new(2026, 10, 30, 0, 40, 0, [TimeSpan]::Zero)
        $script:Next = [DateTimeOffset]::new(2026, 10, 30, 12, 37, 30, [TimeSpan]::Zero)
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ PartitionKey = 'Timer'; RowKey = '9b0c8e50-f798-49db-9a8b-dbcc0fcadeea'; LastFired = $script:Fired; NextFire = $script:Next; JitterSeconds = 450; Timezone = 'Europe/London' }
        }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Remove-CIPPAzDataTableEntity { }
    }
    AfterEach { $env:CIPPNG = $script:OriginalNG; $env:CIPPRootPath = $script:OriginalRoot }

    It 'lists every timer with the state Craft recorded, jitter included' {
        $Timers = @(Get-CIPPTimerFunctions -ListAllTasks)
        $Timers.Count | Should -Be @(Get-Content -Raw (Join-Path $BackendRoot 'Config/CIPPTimers.json') | ConvertFrom-Json).Count

        $Standards = $Timers.Where({ $_.Command -eq 'Start-StandardsOrchestrator' })[0]
        $Standards.LastOccurrence | Should -Be $script:Fired
        $Standards.NextOccurrence | Should -Be $script:Next
        $Standards.JitterMinutes | Should -Be 15
        $Standards.JitterDelay | Should -Be '00:07:30'
        $Standards.Timezone | Should -Be 'Europe/London'

        $Unrecorded = $Timers.Where({ $_.Command -eq 'Start-UserTasksOrchestrator' })[0]
        $Unrecorded.LastOccurrence | Should -BeNullOrEmpty
        $Unrecorded.JitterMinutes | Should -Be 0
    }

    It 'never writes the rows Craft owns' {
        $null = Get-CIPPTimerFunctions -ResetToDefault
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
    }
}
