function Invoke-CIPPOffboardingJob {
    [CmdletBinding()]
    param (
        [string]$TenantFilter,
        [string]$Username,
        [switch]$RunScheduled,
        $Options,
        $APIName = 'Offboard user',
        $Headers,
        $TaskInfo,
        # Live-progress job created by the caller; when set, the user's status row is kept up to date
        [string]$DeploymentId,
        # Zero-based indices of the steps to run again (a step re-run); empty runs every selected task
        [int[]]$StepIndexes = @()
    )

    try {
        if ($Options -is [string]) {
            $Options = $Options | ConvertFrom-Json
        }

        Write-Information "Starting offboarding job for $Username in tenant $TenantFilter"

        # Get user information needed for various tasks
        $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)?`$select=id,displayName,onPremisesSyncEnabled,onPremisesImmutableId" -tenantid $TenantFilter
        $UserID = $User.id
        $DisplayName = $User.displayName

        # Resolve OOO once; empty TipTap HTML must not enable automatic replies
        $OooMessage = $null
        if (-not (Test-CIPPHtmlIsEmpty -Html ([string]$Options.OOO))) {
            $OooMessage = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Options.OOO
        }

        # Build dynamic batch of offboarding tasks based on selected options
        $Batch = [System.Collections.Generic.List[object]]::new()

        # When the user is being deleted, only user removal and OneDrive access grants remain valid; every other task is skipped regardless of its flag
        $DeleteUserSelected = $Options.DeleteUser -eq $true
        $AllowedCmdletsWhenDeletingUser = @('Remove-CIPPUser', 'Set-CIPPSharePointPerms')
        $SkippedForDeleteUser = [System.Collections.Generic.List[string]]::new()

        # Build list of tasks in execution order with their cmdlets.
        # The account-only wipe must run before session revocation, sign-in disable and device removal:
        # the wipe is delivered on the device's next Exchange connection, so the account must still be
        # able to authenticate and the ActiveSync partnership must still exist when it is issued.
        $TaskOrder = @(
            @{
                Title      = 'Wipe mobile devices (account data only)'
                Condition  = { $Options.WipeMobile -eq $true }
                Cmdlet     = 'Clear-CIPPMobileDevice'
                Parameters = @{
                    userid       = $UserID
                    username     = $Username
                    tenantFilter = $TenantFilter
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Revoke all sessions'
                Condition  = { $Options.RevokeSessions -eq $true }
                Cmdlet     = 'Revoke-CIPPSessions'
                Parameters = @{
                    tenantFilter = $TenantFilter
                    username     = $Username
                    userid       = $UserID
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Reset password'
                Condition  = { $Options.ResetPass -eq $true }
                Cmdlet     = 'Set-CIPPResetPassword'
                Parameters = @{
                    tenantFilter = $TenantFilter
                    DisplayName  = $DisplayName
                    UserID       = $Username
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Disable sign in'
                Condition  = { $Options.DisableSignIn -eq $true }
                Cmdlet     = 'Set-CIPPSignInState'
                Parameters = @{
                    TenantFilter   = $TenantFilter
                    userid         = $Username
                    AccountEnabled = $false
                    APIName        = $APIName
                    Headers        = $Headers
                }
            }
            @{
                Title      = 'Hide from Global Address List'
                Condition  = { $Options.HideFromGAL -eq $true }
                Cmdlet     = 'Set-CIPPHideFromGAL'
                Parameters = @{
                    tenantFilter = $TenantFilter
                    UserID       = $Username
                    hidefromgal  = $true
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Remove from all groups'
                Condition  = { $Options.RemoveGroups -eq $true }
                Cmdlet     = 'Remove-CIPPGroups'
                Parameters = @{
                    userid       = $UserID
                    tenantFilter = $TenantFilter
                    APIName      = $APIName
                    Username     = $Username
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Remove all rules'
                Condition  = { $Options.RemoveRules -eq $true }
                Cmdlet     = 'Remove-CIPPMailboxRule'
                Parameters = @{
                    userid         = $UserID
                    username       = $Username
                    tenantFilter   = $TenantFilter
                    APIName        = $APIName
                    RemoveAllRules = $true
                    Headers        = $Headers
                }
            }
            @{
                Title      = 'Remove all mobile devices'
                Condition  = { $Options.RemoveMobile -eq $true }
                Cmdlet     = 'Remove-CIPPMobileDevice'
                Parameters = @{
                    userid       = $UserID
                    username     = $Username
                    tenantFilter = $TenantFilter
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Cancel all calendar invites'
                Condition  = { $Options.removeCalendarInvites -eq $true }
                Cmdlet     = 'Remove-CIPPCalendarInvites'
                Parameters = @{
                    UserID       = $UserID
                    Username     = $Username
                    TenantFilter = $TenantFilter
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Set Out of Office message'
                Condition  = { -not [string]::IsNullOrEmpty($OooMessage) }
                Cmdlet     = 'Set-CIPPOutOfOffice'
                Parameters = @{
                    tenantFilter    = $TenantFilter
                    UserID          = $Username
                    InternalMessage = $OooMessage
                    ExternalMessage = $OooMessage
                    APIName         = $APIName
                    state           = 'Enabled'
                    Headers         = $Headers
                }
            }
            @{
                Title      = 'Forward email'
                Condition  = { ![string]::IsNullOrEmpty($Options.forward) }
                Cmdlet     = 'Set-CIPPForwarding'
                Parameters = @{
                    userid       = $UserID
                    username     = $Username
                    tenantFilter = $TenantFilter
                    Forward      = $Options.forward.value
                    KeepCopy     = [bool]$Options.KeepCopy
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Disable email forwarding'
                Condition  = { $Options.disableForwarding -eq $true }
                Cmdlet     = 'Set-CIPPForwarding'
                Parameters = @{
                    userid       = $UserID
                    username     = $Username
                    tenantFilter = $TenantFilter
                    Disable      = $true
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Grant OneDrive full access'
                Condition  = { $Options.OnedriveAccess.Count -gt 0 }
                Cmdlet     = 'Set-CIPPSharePointPerms'
                Parameters = @{
                    tenantFilter       = $TenantFilter
                    userid             = $Username
                    OnedriveAccessUser = $Options.OnedriveAccess
                    APIName            = $APIName
                    Headers            = $Headers
                }
            }
            @{
                Title      = 'Disable OneDrive sharing links'
                Condition  = { $Options.DisableOneDriveSharing -eq $true }
                Cmdlet     = 'Set-CIPPOneDriveSharing'
                Parameters = @{
                    TenantFilter      = $TenantFilter
                    UserId            = $Username
                    SharingCapability = 'Disabled'
                    APIName           = $APIName
                    Headers           = $Headers
                }
            }
            @{
                Title      = 'Grant full access (no automap)'
                Condition  = { $Options.AccessNoAutomap.Count -gt 0 }
                Cmdlet     = 'Set-CIPPMailboxAccess'
                Parameters = @{
                    tenantFilter = $TenantFilter
                    userid       = $Username
                    AccessUser   = $Options.AccessNoAutomap
                    Automap      = $false
                    AccessRights = @('FullAccess')
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Grant full access (automap)'
                Condition  = { $Options.AccessAutomap.Count -gt 0 }
                Cmdlet     = 'Set-CIPPMailboxAccess'
                Parameters = @{
                    tenantFilter = $TenantFilter
                    userid       = $Username
                    AccessUser   = $Options.AccessAutomap
                    Automap      = $true
                    AccessRights = @('FullAccess')
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Grant Send As access'
                Condition  = { $Options.AccessSendAs.Count -gt 0 }
                Cmdlet     = 'Set-CIPPMailboxAccess'
                Parameters = @{
                    tenantFilter    = $TenantFilter
                    userid          = $Username
                    AccessUser      = $Options.AccessSendAs
                    PermissionLevel = 'SendAs'
                    APIName         = $APIName
                    Headers         = $Headers
                }
            }
            @{
                Title      = 'Grant Send on Behalf access'
                Condition  = { $Options.AccessSendOnBehalf.Count -gt 0 }
                Cmdlet     = 'Set-CIPPMailboxAccess'
                Parameters = @{
                    tenantFilter    = $TenantFilter
                    userid          = $Username
                    AccessUser      = $Options.AccessSendOnBehalf
                    PermissionLevel = 'SendOnBehalf'
                    APIName         = $APIName
                    Headers         = $Headers
                }
            }
            @{
                Title      = 'Remove user''s mailbox permissions'
                Condition  = { $Options.removePermissions -eq $true }
                Cmdlet     = 'Remove-CIPPMailboxPermissions'
                Parameters = @{
                    AccessUser   = $Username
                    TenantFilter = $TenantFilter
                    UseCache     = $true
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Remove user''s calendar permissions'
                Condition  = { $Options.removeCalendarPermissions -eq $true }
                Cmdlet     = 'Remove-CIPPCalendarPermissions'
                Parameters = @{
                    UserToRemove = $Username
                    TenantFilter = $TenantFilter
                    UseCache     = $true
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Convert to shared mailbox'
                Condition  = { $Options.ConvertToShared -eq $true }
                Cmdlet     = 'Set-CIPPMailboxType'
                Parameters = @{
                    tenantFilter = $TenantFilter
                    userid       = $UserID
                    username     = $Username
                    MailboxType  = 'Shared'
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Remove all MFA devices'
                Condition  = { $Options.RemoveMFADevices -eq $true }
                Cmdlet     = 'Remove-CIPPUserMFA'
                Parameters = @{
                    UserPrincipalName = $Username
                    TenantFilter      = $TenantFilter
                    APIName           = $APIName
                    Headers           = $Headers
                }
            }
            @{
                Title      = 'Remove Teams Phone DID'
                Condition  = { $Options.RemoveTeamsPhoneDID -eq $true }
                Cmdlet     = 'Remove-CIPPUserTeamsPhoneDIDs'
                Parameters = @{
                    userid       = $UserID
                    username     = $Username
                    tenantFilter = $TenantFilter
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Remove licenses'
                Condition  = { $Options.RemoveLicenses -eq $true }
                Cmdlet     = 'Remove-CIPPLicense'
                Parameters = @{
                    userid       = $UserID
                    username     = $Username
                    tenantFilter = $TenantFilter
                    APIName      = $APIName
                    Schedule     = $true
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Clear Immutable ID'
                Condition  = { $Options.ClearImmutableId -eq $true }
                Cmdlet     = 'Clear-CIPPImmutableID'
                Parameters = @{
                    UserID       = $UserID
                    Username     = $Username
                    TenantFilter = $TenantFilter
                    User         = $User
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
            @{
                Title      = 'Delete user'
                Condition  = { $Options.DeleteUser -eq $true }
                Cmdlet     = 'Remove-CIPPUser'
                Parameters = @{
                    UserID       = $UserID
                    Username     = $Username
                    TenantFilter = $TenantFilter
                    APIName      = $APIName
                    Headers      = $Headers
                }
            }
        )

        # Build batch from selected tasks
        foreach ($Task in $TaskOrder) {
            if (-not (& $Task.Condition)) {
                continue
            }

            if ($DeleteUserSelected -and $Task.Cmdlet -notin $AllowedCmdletsWhenDeletingUser) {
                $SkippedForDeleteUser.Add($Task.Cmdlet)
                continue
            }

            $Batch.Add(@{
                    FunctionName = 'CIPPOffboardingTask'
                    Cmdlet       = $Task.Cmdlet
                    Title        = $Task.Title
                    Parameters   = $Task.Parameters
                })
        }

        if ($SkippedForDeleteUser.Count -gt 0) {
            $SkippedMessage = "Delete user selected for $Username. Skipped tasks: $($SkippedForDeleteUser -join ', ')"
            Write-Information $SkippedMessage
            Write-LogMessage -API $APIName -tenant $TenantFilter -message $SkippedMessage -sev Info
        }

        if ($Batch.Count -eq 0) {
            $NoTasksMessage = "No offboarding tasks were selected for $Username. The offboarding job was not executed - check that at least one action was enabled."
            Write-LogMessage -API $APIName -tenant $TenantFilter -message $NoTasksMessage -sev Error
            throw $NoTasksMessage
        }

        Write-Information "Built batch of $($Batch.Count) offboarding tasks for $Username"

        # Live progress: the wizard pre-created a queued row per user under this job id. Replace it with
        # the real step list and stamp every task with its step, so the workers (which run in parallel)
        # each report to their own step.
        if ($DeploymentId) {
            if ($StepIndexes.Count -gt 0) {
                # Re-running selected steps: keep the row and reset only those steps.
                foreach ($Index in $StepIndexes) {
                    Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $Username -StepIndex $Index -StepStatus 'pending' -Message 'Waiting to start'
                }
            } else {
                # Notification channels configured on the task are steps from the start, so the row does
                # not look finished while the deliveries are still being made.
                $NotifySteps = @(
                    foreach ($Channel in @(([string]$TaskInfo.PostExecution -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                        @{ Title = "Notify via $Channel"; Kind = 'notify'; Message = 'Sent once every action has finished' }
                    }
                )
                try {
                    $null = New-CIPPAsyncDeployment -JobId $DeploymentId -Names @($Username) -StepTitles (@($Batch | ForEach-Object { $_.Title }) + $NotifySteps) -Source 'Offboarding' -TaskId $TaskInfo.RowKey -TenantFilter $TenantFilter
                } catch {
                    # Progress is a nice-to-have: a storage hiccup here must not fail the offboarding itself.
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Could not write the progress row for $Username : $($_.Exception.Message)" -sev Warn
                }
            }
            for ($i = 0; $i -lt $Batch.Count; $i++) {
                $Batch[$i].DeploymentId = $DeploymentId
                $Batch[$i].DeploymentName = $Username
                $Batch[$i].StepIndex = $i
            }
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Username -Status 'running'
        }

        if ($StepIndexes.Count -gt 0) {
            # Step re-run: the full list above keeps the indices stable; only the requested steps run.
            $Batch = [System.Collections.Generic.List[object]]@($StepIndexes | Where-Object { $_ -ge 0 -and $_ -lt $Batch.Count } | ForEach-Object { $Batch[$_] })
            if ($Batch.Count -eq 0) {
                throw "None of the requested steps ($($StepIndexes -join ', ')) exist for $Username"
            }
        }

        # Start orchestration.
        #
        # Offboarding steps must run in payload order — a later step can undo an earlier one if they race
        # (e.g. convert-to-shared reverting mailbox grants added a step earlier). DurableMode='Sequence' is
        # the legacy Azure Functions durable flag and is kept for that host; Craft ignores it and instead
        # honours Sequential, which pins the whole run to ONE worker and runs the steps one at a time in
        # order. Start-CIPPOrchestrator probes the Craft bridge arity, so on a Craft too old to know
        # Sequential it logs a warning and falls back to fan-out rather than failing — safe here because the
        # grant steps are already idempotent (they read the ACE back), so the ordering is belt-and-suspenders.
        $InputObject = [PSCustomObject]@{
            OrchestratorName = "OffboardingUser_$($Username)_$TenantFilter"
            Batch            = @($Batch)
            SkipLog          = $true
            DurableMode      = 'Sequence'
            Sequential       = $true
        }

        # Add post-execution handler if TaskInfo is provided (from scheduled task)
        $InputObject | Add-Member -NotePropertyName PostExecution -NotePropertyValue @{
            FunctionName = 'CIPPOffboardingComplete'
            Parameters   = @{
                TaskInfo     = $TaskInfo ?? $null
                TenantFilter = $TenantFilter
                Username     = $Username
                Headers      = $Headers
                DeploymentId = $DeploymentId
            }
        }

        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started offboarding job for $Username with ID = '$InstanceId'"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Started offboarding job for $Username with $($Batch.Count) tasks. Instance ID: $InstanceId" -sev Info

        return "Offboarding job started for $Username with $($Batch.Count) tasks"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Failed to start offboarding job for $Username : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        if ($DeploymentId) {
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Username -Status 'failed' -Logs $ErrorMessage.NormalizedError
        }
        throw $ErrorMessage
    }
}
