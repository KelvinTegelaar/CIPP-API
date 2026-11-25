# Pester tests for Invoke-ExecOnboardUser: request validation, the task it queues for
# Invoke-CIPPOnboardingJob, and the guards on the re-run actions.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecOnboardUser.ps1'

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, [switch]$RunNow, $RowKey) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TenantFilter) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Assert-CippPrivilegedUserAccess { param($TenantFilter, $UserId) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Get-CIPPPrivilegedUserTaskTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function New-OnboardRequest {
        param([hashtable]$Body = @{}, [hashtable]$Query = @{})
        $RequestBody = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            user         = [pscustomobject]@{ value = 'maria@contoso.com' }
            Fixes        = @([pscustomobject]@{ Key = 'EnableSignIn'; Params = [pscustomobject]@{} })
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{ Body = $RequestBody; Headers = @{}; Params = @{ CIPPEndpoint = 'ExecOnboardUser' }; Query = $Query }
    }

    function New-StoredTask {
        param([string]$Command = 'Invoke-CIPPOnboardingJob', [string]$Tenant = 'contoso.com')
        [pscustomobject]@{
            RowKey     = 'task-1'
            Command    = $Command
            Tenant     = $Tenant
            Reference  = 'ticket-42'
            Parameters = (@{ Username = 'maria@contoso.com'; Options = @{ Fixes = @(@{ Key = 'EnableSignIn' }, @{ Key = 'ResetPassword' }) }; DeploymentId = 'job-1' } | ConvertTo-Json -Compress -Depth 10)
        }
    }
}

Describe 'Invoke-ExecOnboardUser' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPScheduledTask { 'Successfully added task: Onboarding' }
        Mock New-CIPPAsyncDeployment { 'job-1' }
        Mock Assert-CippPrivilegedUserAccess { }
        Mock Get-CIPPTable { @{} }
    }

    Context 'Validation' {
        It 'rejects an unknown key and names it' {
            $Fixes = @([pscustomobject]@{ Key = 'EnableSignIn' }, [pscustomobject]@{ Key = 'AssignAdminRole' })
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ Fixes = $Fixes })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            ($Response.Body.Results -join ' ') | Should -BeLike '*Unknown fix key(s): AssignAdminRole.*'
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            Should -Invoke New-CIPPAsyncDeployment -Times 0 -Exactly
        }

        It 'rejects <Case>' -ForEach @(
            @{ Case = 'empty Fixes'; Body = @{ Fixes = @() }; Like = "*'Fixes' is required*" }
            @{ Case = 'missing Fixes'; Body = @{ Fixes = $null }; Like = "*'Fixes' is required*" }
            @{ Case = 'a missing user'; Body = @{ user = $null }; Like = "*'user' is required*" }
            @{ Case = 'two users'; Body = @{ user = @('a@contoso.com', 'b@contoso.com') }; Like = "*'user' is required*" }
            @{ Case = 'a user that would change the Graph path'; Body = @{ user = 'a@contoso.com/manager' }; Like = "*'user' is required*" }
            @{ Case = 'a missing tenant'; Body = @{ tenantFilter = '' }; Like = "*'tenantFilter' is required*" }
            @{ Case = 'a schedule without a date'; Body = @{ Scheduled = @{ enabled = $true; date = 0 } }; Like = '*Scheduled.date*' }
        ) {
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body $Body)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            ($Response.Body.Results -join ' ') | Should -BeLike $Like
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }
    }

    Context 'Queueing the job' {
        It 'queues one run-now onboarding job and returns the job id' {
            $Fixes = @(
                [pscustomobject]@{ Key = 'RemoveMailboxPermissions'; Params = [pscustomobject]@{ Items = @([pscustomobject]@{ User = 'tom@contoso.com'; AccessRights = @('FullAccess') }) } }
                [pscustomobject]@{ Key = 'EnableSignIn'; Params = [pscustomobject]@{} }
            )
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ Fixes = $Fixes; reference = 'ticket-42'; PsaTicketId = '77'; PostExecution = @{ email = $true } })

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $Response.Body.DeploymentId | Should -Be 'job-1'
            Should -Invoke New-CIPPAsyncDeployment -Times 1 -Exactly -ParameterFilter { $Source -eq 'Onboarding' -and (@($Names) -join ',') -eq 'maria@contoso.com' -and $TenantFilter -eq 'contoso.com' }
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $RunNow -and $Task.Command.value -eq 'Invoke-CIPPOnboardingJob' -and $Task.Name -eq 'Onboarding: maria@contoso.com' -and
                $Task.TenantFilter -eq 'contoso.com' -and $Task.Parameters.Username -eq 'maria@contoso.com' -and $Task.Parameters.DeploymentId -eq 'job-1' -and
                (@($Task.Parameters.Options.Fixes.Key) -join ',') -eq 'RemoveMailboxPermissions,EnableSignIn' -and
                $Task.Parameters.Options.Fixes[0].Params.Items[0].User -eq 'tom@contoso.com' -and
                $Task.Reference -eq 'ticket-42' -and $Task.PsaTicketId -eq '77' -and $Task.PostExecution.Email -eq $true -and $Task.PostExecution.Webhook -eq $false
            }
        }

        It 'accepts the user as a plain string' {
            $null = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ user = 'maria@contoso.com' })
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $Task.Parameters.Username -eq 'maria@contoso.com' }
        }

        It 'schedules for later without a job id to poll' {
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ Scheduled = @{ enabled = $true; date = 1900000000 } })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $Response.Body.PSObject.Properties.Name | Should -Not -Contain 'DeploymentId'
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { -not $RunNow -and $Task.ScheduledTime -eq 1900000000 }
        }

        It 'does not check the user for privileged roles when the job has no account step' {
            Mock Assert-CippPrivilegedUserAccess { throw 'Could not check whether maria@contoso.com holds a privileged role: does not exist' }
            $Fixes = @('EnableArchive', 'AddGroups', 'GrantMailboxAccess', 'ConvertToUserMailbox' | ForEach-Object { [pscustomobject]@{ Key = $_; Params = [pscustomobject]@{} } })
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ Fixes = $Fixes })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Assert-CippPrivilegedUserAccess -Times 0 -Exactly
        }

        It 'checks the user when the job has the account step <Key>' -ForEach @(
            @{ Key = 'EnableSignIn' }, @{ Key = 'ResetPassword' }, @{ Key = 'IssueTAP' }
        ) {
            $Fixes = @([pscustomobject]@{ Key = 'EnableArchive'; Params = [pscustomobject]@{} }, [pscustomobject]@{ Key = $Key; Params = [pscustomobject]@{} })
            $null = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ Fixes = $Fixes })
            Should -Invoke Assert-CippPrivilegedUserAccess -Times 1 -Exactly -ParameterFilter { $UserId -eq 'maria@contoso.com' }
        }

        It 'accepts the post-licence keys' {
            $Fixes = @('ProvisionOneDrive', 'SetMailboxLocale', 'EnableArchive', 'GrantMailboxAccess', 'GrantCalendarAccess', 'AddOneDriveShortcuts' | ForEach-Object { [pscustomobject]@{ Key = $_; Params = [pscustomobject]@{} } })
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ Fixes = $Fixes })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { @($Task.Parameters.Options.Fixes.Key).Count -eq 6 }
        }

        It 'refuses a privileged user and queues nothing' {
            Mock Assert-CippPrivilegedUserAccess { throw [System.UnauthorizedAccessException]::new('maria@contoso.com holds a privileged admin role.') }
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest)
            $Response.StatusCode | Should -Not -Be ([HttpStatusCode]::OK)
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            Should -Invoke Assert-CippPrivilegedUserAccess -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $UserId -eq 'maria@contoso.com' }
        }

        It 'does not answer 200 when the scheduler refuses the task' {
            Mock Add-CIPPScheduledTask { 'Error - Push (notify me) was selected but you have no push notification devices registered.' }
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest)
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $Response.Body.PSObject.Properties.Name | Should -Not -Contain 'DeploymentId'
        }
    }

    Context 'Re-run' {
        It 'refuses <Case>' -ForEach @(
            @{ Case = 'a task from another tenant'; Task = @{ Tenant = 'fabrikam.com' } }
            @{ Case = 'a task of another command'; Task = @{ Command = 'Invoke-CIPPOffboardingJob' } }
        ) {
            $Stored = New-StoredTask @Task
            Mock Get-CIPPAzDataTableEntity { $Stored }
            foreach ($Action in 'Rerun', 'RerunStep') {
                $Request = New-OnboardRequest -Body @{ TaskId = 'task-1'; StepIndex = 0 } -Query @{ Action = $Action }
                $Response = Invoke-ExecOnboardUser -Request $Request
                $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
            }
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            Should -Invoke Assert-CippPrivilegedUserAccess -Times 0 -Exactly
        }

        It 'refuses a task that does not exist' {
            Mock Get-CIPPAzDataTableEntity { }
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ TaskId = 'nope' } -Query @{ Action = 'Rerun' })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
        }

        It 'checks the stored user for privileged roles before any re-run' {
            Mock Get-CIPPAzDataTableEntity { New-StoredTask }
            Mock Assert-CippPrivilegedUserAccess { throw [System.UnauthorizedAccessException]::new('privileged') }
            foreach ($Action in 'Rerun', 'RerunStep') {
                $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ TaskId = 'task-1'; StepIndex = 0 } -Query @{ Action = $Action })
                $Response.StatusCode | Should -Not -Be ([HttpStatusCode]::OK)
            }
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            Should -Invoke Assert-CippPrivilegedUserAccess -Times 2 -Exactly -ParameterFilter { $UserId -eq 'maria@contoso.com' -and $TenantFilter -eq 'contoso.com' }
        }

        It 'queues the whole task again on Rerun' {
            Mock Get-CIPPAzDataTableEntity { New-StoredTask }
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ TaskId = 'task-1' } -Query @{ Action = 'Rerun' })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $RunNow -and $RowKey -eq 'task-1' }
        }

        It 'queues one step from the stored parameters on RerunStep' {
            Mock Get-CIPPAzDataTableEntity { New-StoredTask }
            $Request = New-OnboardRequest -Body @{ TaskId = 'task-1'; StepIndex = 1; StepTitle = 'Reset password'; Fixes = @([pscustomobject]@{ Key = 'IssueTAP' }) } -Query @{ Action = 'RerunStep' }
            $Response = Invoke-ExecOnboardUser -Request $Request
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $RunNow -and $Task.Command.value -eq 'Invoke-CIPPOnboardingJob' -and $Task.TenantFilter -eq 'contoso.com' -and
                $Task.Name -eq 'Onboarding: maria@contoso.com - re-run Reset password' -and $Task.Parameters.Username -eq 'maria@contoso.com' -and
                $Task.Parameters.DeploymentId -eq 'job-1' -and (@($Task.Parameters.StepIndexes) -join ',') -eq '1' -and
                (@($Task.Parameters.Options.Fixes.Key) -join ',') -eq 'EnableSignIn,ResetPassword' -and $Task.Reference -eq 'ticket-42'
            }
        }

        It 'needs a step index for RerunStep' {
            Mock Get-CIPPAzDataTableEntity { New-StoredTask }
            $Response = Invoke-ExecOnboardUser -Request (New-OnboardRequest -Body @{ TaskId = 'task-1' } -Query @{ Action = 'RerunStep' })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        }
    }
}
