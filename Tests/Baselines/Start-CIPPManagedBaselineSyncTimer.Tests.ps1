# The hourly check on custom managed baseline requests. It must call nothing while the
# integration is off, and only ask about requests that can actually have moved.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [string]$OperationType) }
    function Write-LogMessage { param($API, $message, $Sev) }
    function Update-CIPPManagedBaselineRequest { param($Row) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Entrypoints/Timer Functions/Start-CIPPManagedBaselineSyncTimer.ps1')

    $script:Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    function New-Row {
        param($Id, $Status, $CollectionStartedAt = $script:Now, $LastChecked = $script:Now, [bool]$ConfirmPending = $false)
        [pscustomobject]@{ RowKey = $Id; Status = $Status; SubmittedAt = 100; CollectionStartedAt = $CollectionStartedAt; LastChecked = $LastChecked; ConfirmPending = $ConfirmPending }
    }
    $script:Enabled = [pscustomobject]@{ config = '{"CyberDrainManagedBaselines":{"Enabled":true}}' }
}

Describe 'Start-CIPPManagedBaselineSyncTimer' {
    BeforeEach {
        $script:Rows = @()
        $script:Config = $script:Enabled
        $script:Failed = [System.Collections.Generic.List[object]]::new()
        Mock Write-LogMessage {}
        Mock Update-CIPPManagedBaselineRequest { 'Waiting on CyberDrain' }
        Mock Add-CIPPAzDataTableEntity { $script:Failed.Add($Entity) }
        Mock Get-CIPPAzDataTableEntity { if ($Context -eq 'Extensionsconfig') { $script:Config } else { $script:Rows } }
    }

    It 'reads and asks nothing while the integration is off' {
        $script:Config = [pscustomobject]@{ config = '{"CyberDrainManagedBaselines":{"Enabled":false}}' }
        $script:Rows = @(New-Row 'a' 'Waiting on CyberDrain')

        Start-CIPPManagedBaselineSyncTimer

        Should -Invoke Update-CIPPManagedBaselineRequest -Times 0 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $Context -eq 'ManagedBaselineRequests' }
    }

    It 'asks about requests that are waiting, ready, owed a confirm call, or implemented and not checked today' {
        $script:Rows = @(
            New-Row 'waiting' 'Waiting on CyberDrain'
            New-Row 'ready' 'Completed - ready to confirm'
            New-Row 'confirm' 'Implemented' -ConfirmPending $true
            New-Row 'stale' 'Implemented' -LastChecked ($script:Now - 90000)
            New-Row 'fresh' 'Implemented'
            New-Row 'failed' 'Failed'
            New-Row 'collecting' 'Waiting on data collection'
        )

        Start-CIPPManagedBaselineSyncTimer

        Should -Invoke Update-CIPPManagedBaselineRequest -Times 4 -Exactly
        foreach ($Id in 'waiting', 'ready', 'confirm', 'stale') {
            Should -Invoke Update-CIPPManagedBaselineRequest -Times 1 -Exactly -ParameterFilter { $Row.RowKey -eq $Id }
        }
        $script:Failed.Count | Should -Be 0
    }

    It 'fails a data collection that has been open for more than six hours, so it can be retried' {
        $script:Rows = @(
            New-Row 'lost' 'Waiting on data collection' -CollectionStartedAt ($script:Now - 30000)
            New-Row 'running' 'Waiting on data collection' -CollectionStartedAt ($script:Now - 600)
        )

        Start-CIPPManagedBaselineSyncTimer

        $script:Failed.RowKey | Should -Be @('lost')
        $script:Failed[0].Status | Should -Be 'Failed'
        $script:Failed[0].Error | Should -BeLike '*Use Retry*'
    }

    It 'stops asking once CyberDrain rejects the key, and says so once' {
        $script:Rows = @((New-Row 'a' 'Waiting on CyberDrain'), (New-Row 'b' 'Waiting on CyberDrain'), (New-Row 'c' 'Waiting on CyberDrain'))
        Mock Update-CIPPManagedBaselineRequest { throw [System.UnauthorizedAccessException]::new('CyberDrain rejected the API key.') }

        Start-CIPPManagedBaselineSyncTimer

        Should -Invoke Update-CIPPManagedBaselineRequest -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'carries on with the next request when one cannot be checked' {
        $script:Rows = @((New-Row 'a' 'Waiting on CyberDrain'), (New-Row 'b' 'Waiting on CyberDrain'))
        Mock Update-CIPPManagedBaselineRequest { throw 'service is down' }

        Start-CIPPManagedBaselineSyncTimer

        Should -Invoke Update-CIPPManagedBaselineRequest -Times 2 -Exactly
    }
}
