function Invoke-CIPPOffboardingJob {
    [CmdletBinding()]
    param (
        [string]$TenantFilter,
        [string]$Username,
        [switch]$RunScheduled,
        $Options,
        $APIName = 'Offboard user',
        $Headers,
        $TaskInfo
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

        # Start orchestration
        $InputObject = [PSCustomObject]@{
            OrchestratorName = "OffboardingUser_$($Username)_$TenantFilter"
            Batch            = @($Batch)
            SkipLog          = $true
            DurableMode      = 'Sequence'
        }

        # Add post-execution handler if TaskInfo is provided (from scheduled task)
        $InputObject | Add-Member -NotePropertyName PostExecution -NotePropertyValue @{
            FunctionName = 'CIPPOffboardingComplete'
            Parameters   = @{
                TaskInfo     = $TaskInfo ?? $null
                TenantFilter = $TenantFilter
                Username     = $Username
                Headers      = $Headers
            }
        }

        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started offboarding job for $Username with ID = '$InstanceId'"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Started offboarding job for $Username with $($Batch.Count) tasks. Instance ID: $InstanceId" -sev Info

        return "Offboarding job started for $Username with $($Batch.Count) tasks"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Failed to start offboarding job for $Username : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw $ErrorMessage
    }
}
