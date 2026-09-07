# Pester tests for Set-CIPPAsyncDeploymentStep.
#
# Offboarding steps run on different workers at the same time and all write into one Steps JSON
# property of the same row. The write is ETag-checked; when it is rejected the function must re-read
# the row so the retry carries the other worker's update instead of overwriting it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/AsyncDeployment/Set-CIPPAsyncDeploymentStep.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Set-CIPPAsyncDeploymentStep.ps1 at $FunctionPath" }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Update-CIPPAzDataTableEntity { param($Context, $Entity, $OperationType, [switch]$Force, $MaxRetries) }

    . $FunctionPath

    function New-Row {
        param([string]$FirstStepStatus = 'pending')
        [pscustomobject]@{
            PartitionKey = 'job-1'
            RowKey       = 'pat@contoso.com'
            ETag         = 'W/"1"'
            Status       = 'running'
            Steps        = (ConvertTo-Json -Compress -InputObject @(
                    @{ Title = 'Revoke all sessions'; Status = $FirstStepStatus; Message = '' }
                    @{ Title = 'Disable sign in'; Status = 'pending'; Message = '' }
                ))
        }
    }
}

Describe 'Set-CIPPAsyncDeploymentStep' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'ctx' } }
        Mock -CommandName Start-Sleep -MockWith { }
    }

    It 'writes the step without -Force so a concurrent update is detected rather than overwritten' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-Row }
        Mock -CommandName Update-CIPPAzDataTableEntity -MockWith { $script:Written.Add($Entity) }

        Set-CIPPAsyncDeploymentStep -JobId 'job-1' -Name 'pat@contoso.com' -StepIndex 1 -StepStatus 'succeeded' -Message 'Done'

        Should -Invoke Update-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { -not $Force }
        $Steps = @($script:Written[0].Steps | ConvertFrom-Json)
        $Steps[1].Status | Should -Be 'succeeded'
        $Steps[1].Message | Should -Be 'Done'
        $Steps[0].Status | Should -Be 'pending'
    }

    It 're-reads the row and retries when the write is rejected, keeping the other worker''s step' {
        # First read: nothing done yet. Second read, after the rejected write: another worker has
        # finished step 0 in between, and that must survive.
        $script:Reads = 0
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            $script:Reads++
            if ($script:Reads -eq 1) { New-Row } else { New-Row -FirstStepStatus 'succeeded' }
        }
        $script:Writes = 0
        Mock -CommandName Update-CIPPAzDataTableEntity -MockWith {
            $script:Writes++
            if ($script:Writes -eq 1) { throw 'Precondition Failed' }
            $script:Written.Add($Entity)
        }

        Set-CIPPAsyncDeploymentStep -JobId 'job-1' -Name 'pat@contoso.com' -StepIndex 1 -StepStatus 'running' -Message 'In progress'

        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly
        Should -Invoke Update-CIPPAzDataTableEntity -Times 2 -Exactly
        $Steps = @($script:Written[0].Steps | ConvertFrom-Json)
        $Steps[0].Status | Should -Be 'succeeded'
        $Steps[1].Status | Should -Be 'running'
    }

    It 'gives up quietly after five rejected writes' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-Row }
        Mock -CommandName Update-CIPPAzDataTableEntity -MockWith { throw 'Precondition Failed' }

        { Set-CIPPAsyncDeploymentStep -JobId 'job-1' -Name 'pat@contoso.com' -StepIndex 0 -StepStatus 'failed' -Message 'x' } | Should -Not -Throw

        Should -Invoke Update-CIPPAzDataTableEntity -Times 5 -Exactly
    }

    It 'trims an oversized message so the row stays writable' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-Row }
        Mock -CommandName Update-CIPPAzDataTableEntity -MockWith { $script:Written.Add($Entity) }

        Set-CIPPAsyncDeploymentStep -JobId 'job-1' -Name 'pat@contoso.com' -StepIndex 0 -StepStatus 'succeeded' -Message ('x' * 5000)

        $Steps = @($script:Written[0].Steps | ConvertFrom-Json)
        $Steps[0].Message.Length | Should -BeLessThan 2100
    }
}
