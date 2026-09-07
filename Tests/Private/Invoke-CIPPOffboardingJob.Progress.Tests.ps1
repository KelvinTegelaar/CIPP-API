# Pester tests for the live-progress wiring in Invoke-CIPPOffboardingJob.
#
# The wizard hands the job a DeploymentId. The job must turn the selected tasks into the step list of
# that user's status row, stamp every queued task with its step so the workers (which run in parallel)
# report to the right place, and close the row as failed when the job never gets as far as queueing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $JobPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    if (-not (Test-Path $JobPath)) { throw "Could not locate Invoke-CIPPOffboardingJob.ps1 at $JobPath" }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TaskId, $TenantFilter) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }

    . $HtmlPath
    . $JobPath
}

Describe 'Invoke-CIPPOffboardingJob live progress' {
    BeforeEach {
        $script:CapturedInput = $null
        $script:StepTitles = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-Information -MockWith { }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'user-id-1'; displayName = 'Pat Lee'; onPremisesSyncEnabled = $false; onPremisesImmutableId = $null }
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { $script:CapturedInput = $InputObject; 'orch-1' }
        Mock -CommandName New-CIPPAsyncDeployment -MockWith { $script:StepTitles = @($StepTitles); $JobId }
        Mock -CommandName Set-CIPPAsyncDeploymentStatus -MockWith { }
        Mock -CommandName Set-CIPPAsyncDeploymentStep -MockWith { }
    }

    It 'gives the row one step per selected task, in execution order, and stamps each task with its step' {
        $Options = [pscustomobject]@{ RevokeSessions = $true; DisableSignIn = $true; RemoveLicenses = $true }

        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options $Options -DeploymentId 'job-1' -TaskInfo ([pscustomobject]@{ RowKey = 'task-1' })

        Should -Invoke New-CIPPAsyncDeployment -Times 1 -Exactly -ParameterFilter {
            $JobId -eq 'job-1' -and (@($Names) -join ',') -eq 'pat@contoso.com' -and $Source -eq 'Offboarding' -and $TaskId -eq 'task-1' -and $TenantFilter -eq 'contoso.com'
        }
        $script:StepTitles | Should -Be @('Revoke all sessions', 'Disable sign in', 'Remove licenses')
        $Batch = @($script:CapturedInput.Batch)
        $Batch.Cmdlet | Should -Be @('Revoke-CIPPSessions', 'Set-CIPPSignInState', 'Remove-CIPPLicense')
        $Batch.StepIndex | Should -Be @(0, 1, 2)
        $Batch.DeploymentId | Should -Be @('job-1', 'job-1', 'job-1')
        $Batch.DeploymentName | Should -Be @('pat@contoso.com', 'pat@contoso.com', 'pat@contoso.com')
        $script:CapturedInput.PostExecution.Parameters.DeploymentId | Should -Be 'job-1'
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -Exactly -ParameterFilter {
            $JobId -eq 'job-1' -and $Name -eq 'pat@contoso.com' -and $Status -eq 'running'
        }
    }

    It 'closes the row as failed when the job cannot even be queued' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'user not found' }

        { Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ RevokeSessions = $true }) -DeploymentId 'job-1' } | Should -Throw

        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -Exactly -ParameterFilter {
            $JobId -eq 'job-1' -and $Status -eq 'failed' -and $Logs -like '*user not found*'
        }
    }

    It 'runs only the requested step and resets just that step on the existing row' {
        $Options = [pscustomobject]@{ RevokeSessions = $true; DisableSignIn = $true; RemoveLicenses = $true }

        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options $Options -DeploymentId 'job-1' -StepIndexes @(1)

        $Batch = @($script:CapturedInput.Batch)
        $Batch.Count | Should -Be 1
        $Batch[0].Cmdlet | Should -Be 'Set-CIPPSignInState'
        $Batch[0].StepIndex | Should -Be 1
        Should -Invoke New-CIPPAsyncDeployment -Times 0 -Exactly
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 1 -Exactly -ParameterFilter {
            $JobId -eq 'job-1' -and $Name -eq 'pat@contoso.com' -and $StepIndex -eq 1 -and $StepStatus -eq 'pending'
        }
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -Exactly -ParameterFilter { $Status -eq 'running' }
    }

    It 'refuses a step re-run for a step that does not exist' {
        $Options = [pscustomobject]@{ RevokeSessions = $true }

        { Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options $Options -DeploymentId 'job-1' -StepIndexes @(7) } | Should -Throw

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'puts a pending notification step per configured channel on the row from the start' {
        $Options = [pscustomobject]@{ RevokeSessions = $true; DisableSignIn = $true }

        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options $Options -DeploymentId 'job-1' -TaskInfo ([pscustomobject]@{ RowKey = 'task-1'; PostExecution = 'Webhook,Email' })

        $script:StepTitles.Count | Should -Be 4
        $script:StepTitles[0] | Should -Be 'Revoke all sessions'
        $script:StepTitles[2].Title | Should -Be 'Notify via Webhook'
        $script:StepTitles[2].Kind | Should -Be 'notify'
        $script:StepTitles[3].Title | Should -Be 'Notify via Email'
        # Notification steps are not tasks: nothing extra is queued for them
        @($script:CapturedInput.Batch).Count | Should -Be 2
    }

    It 'still starts the offboarding when the progress row cannot be written' {
        Mock -CommandName New-CIPPAsyncDeployment -MockWith { throw 'An error occurred while sending the request.' }

        $Result = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ RevokeSessions = $true }) -DeploymentId 'job-1'

        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly
        $Result | Should -BeLike 'Offboarding job started*'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warn' -and $message -like '*progress row*' }
    }

    It 'leaves progress alone when no job id was given' {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ RevokeSessions = $true })

        Should -Invoke New-CIPPAsyncDeployment -Times 0 -Exactly
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 0 -Exactly
        @($script:CapturedInput.Batch)[0].Keys | Should -Not -Contain 'DeploymentId'
    }
}
