# Pester tests for the live-progress reporting in Push-CIPPOffboardingTask.
#
# The activity runs one offboarding cmdlet and reports to the step the job stamped on it. Most
# cmdlets do not throw for per-item problems - Remove-CIPPGroups returns 'Error: ...' lines next to
# 'Successfully removed ...' lines - so a returned error line must show as a failed step, or the
# progress view says Succeeded over a message that starts with Error.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-CIPPOffboardingTask.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Push-CIPPOffboardingTask.ps1 at $FunctionPath" }

    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Write-Information { param($MessageData) }

    . $FunctionPath

    # The activity only runs cmdlets it can find in the CIPPCore module, so the fakes live in a
    # throwaway module of that name. Remove-CIPPGroups hands back whatever the test put in
    # $global:CippTestResult; Set-CIPPSignInState always throws.
    $script:FakeCore = New-Module -Name CIPPCore -ScriptBlock {
        function Remove-CIPPGroups { param($userid, $tenantFilter) $global:CippTestResult }
        function Set-CIPPSignInState { param($userid, $TenantFilter) throw 'boom' }
    } | Import-Module -PassThru -Force

    function New-TaskItem {
        param([string]$Cmdlet, [switch]$NoJob)
        $Item = [pscustomobject]@{
            FunctionName = 'CIPPOffboardingTask'
            Cmdlet       = $Cmdlet
            Parameters   = @{ userid = 'user-id-1'; tenantFilter = 'contoso.com' }
        }
        if (-not $NoJob) {
            $Item | Add-Member -NotePropertyName DeploymentId -NotePropertyValue 'job-1'
            $Item | Add-Member -NotePropertyName DeploymentName -NotePropertyValue 'pat@contoso.com'
            $Item | Add-Member -NotePropertyName StepIndex -NotePropertyValue 2
        }
        $Item
    }
}

AfterAll {
    Remove-Module -Name CIPPCore -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name CippTestResult -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Push-CIPPOffboardingTask live progress' {
    BeforeEach {
        Mock -CommandName Write-Information -MockWith { }
        Mock -CommandName Set-CIPPAsyncDeploymentStep -MockWith { }
    }

    It 'marks the step failed when the cmdlet returns an error line without throwing' {
        $global:CippTestResult = @(
            "Error: Could not remove pat@contoso.com from group 'All Users' because it is a Dynamic Group."
            "Successfully removed pat@contoso.com from group 'Sales'"
        )

        $null = Push-CIPPOffboardingTask -Item (New-TaskItem -Cmdlet 'Remove-CIPPGroups')

        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter {
            $JobId -eq 'job-1' -and $Name -eq 'pat@contoso.com' -and $StepIndex -eq 2 -and $StepStatus -eq 'running'
        }
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter {
            $StepStatus -eq 'failed' -and $Message -eq "Error: Could not remove pat@contoso.com from group 'All Users' because it is a Dynamic Group.`nSuccessfully removed pat@contoso.com from group 'Sales'"
        }
    }

    It 'marks the step succeeded and keeps every returned line' {
        $global:CippTestResult = @('Successfully removed pat@contoso.com from group Sales', 'Successfully removed pat@contoso.com from group Ops')

        $Result = Push-CIPPOffboardingTask -Item (New-TaskItem -Cmdlet 'Remove-CIPPGroups')

        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter {
            $StepStatus -eq 'succeeded' -and $Message -eq "Successfully removed pat@contoso.com from group Sales`nSuccessfully removed pat@contoso.com from group Ops"
        }
        @($Result).Count | Should -Be 2
    }

    It 'marks the step failed with the error text when the cmdlet throws' {
        $Result = Push-CIPPOffboardingTask -Item (New-TaskItem -Cmdlet 'Set-CIPPSignInState')

        $Result | Should -Be 'Failed to execute Set-CIPPSignInState : boom'
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter {
            $StepStatus -eq 'failed' -and $Message -eq 'Failed to execute Set-CIPPSignInState : boom'
        }
    }

    It 'leaves progress alone when the task carries no job id' {
        $global:CippTestResult = 'done'

        $null = Push-CIPPOffboardingTask -Item (New-TaskItem -Cmdlet 'Remove-CIPPGroups' -NoJob)

        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 0 -Exactly
    }
}
