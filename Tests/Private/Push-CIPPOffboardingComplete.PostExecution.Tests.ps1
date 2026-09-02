# Pester tests for the post-execution tracking in Push-CIPPOffboardingComplete.
#
# When an offboarding task has notification channels configured, the delivery outcome of each one
# must be kept with the task (PostExecutionResults) and appended to the user's progress row as a
# step, so a webhook that returned 500 is as visible as a cmdlet that failed.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-CIPPOffboardingComplete.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Push-CIPPOffboardingComplete.ps1 at $FunctionPath" }

    function Get-CippTable { param($tablename) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Write-Information { param($MessageData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Send-CIPPScheduledTaskAlert { param($Results, $TaskInfo, $TenantFilter, $TaskType) }
    function Get-CIPPAsyncDeployment { param($JobId) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Add-CIPPAsyncDeploymentStep { param($JobId, $Name, $Title, $StepStatus, $Message, $Kind) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }

    . $FunctionPath

    function New-CompletionItem {
        param([string]$PostExecution = 'Webhook,Email')
        [pscustomobject]@{
            Parameters = [pscustomobject]@{
                TaskInfo     = [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; PostExecution = $PostExecution }
                TenantFilter = 'contoso.com'
                Username     = 'pat@contoso.com'
                Headers      = @{}
                DeploymentId = 'job-1'
            }
            Results    = @('Successfully revoked sessions for pat@contoso.com')
        }
    }
}

Describe 'Push-CIPPOffboardingComplete post-execution tracking' {
    BeforeEach {
        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'ctx' } }
        Mock -CommandName Update-AzDataTableEntity -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-Information -MockWith { }
        Mock -CommandName Set-CIPPAsyncDeploymentStatus -MockWith { }
        Mock -CommandName Add-CIPPAsyncDeploymentStep -MockWith { }
        Mock -CommandName Set-CIPPAsyncDeploymentStep -MockWith { }
        Mock -CommandName Send-CIPPScheduledTaskAlert -MockWith {
            @(
                [pscustomobject]@{ Channel = 'Webhook'; Result = 'Error: Webhook returned status code 500 for https://hooks.example' }
                [pscustomobject]@{ Channel = 'Email'; Result = 'Sent an email alert: Offboarding' }
            )
        }
        # The row as the job created it: the action steps, then one pending notification step per channel.
        Mock -CommandName Get-CIPPAsyncDeployment -MockWith {
            [pscustomobject]@{
                Name  = 'pat@contoso.com'
                Steps = @(
                    [pscustomobject]@{ Title = 'Revoke all sessions'; Status = 'succeeded' }
                    [pscustomobject]@{ Title = 'Remove from all groups'; Status = 'failed' }
                    [pscustomobject]@{ Title = 'Notify via Webhook'; Status = 'pending'; Kind = 'notify' }
                    [pscustomobject]@{ Title = 'Notify via Email'; Status = 'pending'; Kind = 'notify' }
                )
            }
        }
    }

    It 'stores each delivery outcome on the task and fills in the matching notification step' {
        $null = Push-CIPPOffboardingComplete -Item (New-CompletionItem)

        Should -Invoke Send-CIPPScheduledTaskAlert -Times 1 -Exactly -ParameterFilter { $TaskType -eq 'User Offboarding' }
        Should -Invoke Update-AzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.RowKey -eq 'task-1' -and $Entity.PostExecutionResults -like '*"Channel":"Webhook"*' -and $Entity.PostExecutionResults -like '*status code 500*'
        }
        # Both notification steps go running while the deliveries are made...
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 2 -Exactly -ParameterFilter { $StepStatus -eq 'running' -and $Message -eq 'Sending' }
        # ...then each one gets its own outcome, at its own index.
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter {
            $JobId -eq 'job-1' -and $Name -eq 'pat@contoso.com' -and $StepIndex -eq 2 -and $StepStatus -eq 'failed' -and $Message -like 'Error: Webhook*'
        }
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter { $StepIndex -eq 3 -and $StepStatus -eq 'succeeded' }
        Should -Invoke Add-CIPPAsyncDeploymentStep -Times 0 -Exactly
    }

    It 'appends the notification step when the row was created without one' {
        Mock -CommandName Get-CIPPAsyncDeployment -MockWith {
            [pscustomobject]@{ Name = 'pat@contoso.com'; Steps = @([pscustomobject]@{ Title = 'Revoke all sessions'; Status = 'succeeded' }) }
        }

        $null = Push-CIPPOffboardingComplete -Item (New-CompletionItem)

        Should -Invoke Add-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter {
            $Title -eq 'Notify via Webhook' -and $StepStatus -eq 'failed' -and $Kind -eq 'notify' -and $Message -like 'Error: Webhook*'
        }
        Should -Invoke Add-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter { $Title -eq 'Notify via Email' -and $StepStatus -eq 'succeeded' }
    }

    It 'closes the progress row as failed when a notification failed' {
        $null = Push-CIPPOffboardingComplete -Item (New-CompletionItem)

        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -Exactly -ParameterFilter { $JobId -eq 'job-1' -and $Status -eq 'failed' }
    }

    It 'sends nothing and records nothing when no channel is configured' {
        $null = Push-CIPPOffboardingComplete -Item (New-CompletionItem -PostExecution '')

        Should -Invoke Send-CIPPScheduledTaskAlert -Times 0 -Exactly
        Should -Invoke Add-CIPPAsyncDeploymentStep -Times 0 -Exactly
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 0 -Exactly
        Should -Invoke Update-AzDataTableEntity -Times 0 -Exactly -ParameterFilter { $null -ne $Entity.PostExecutionResults }
    }
}
