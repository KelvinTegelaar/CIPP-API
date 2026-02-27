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

        # Build dynamic batch of offboarding tasks based on selected options
        $Batch = [System.Collections.Generic.List[object]]::new()

        # Build list of tasks in execution order with their cmdlets
        $TaskOrder = @(
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
                Condition  = { ![string]::IsNullOrEmpty($Options.OOO) }
                Cmdlet     = 'Set-CIPPOutOfOffice'
                Parameters = @{
                    tenantFilter    = $TenantFilter
                    UserID          = $Username
                    InternalMessage = $Options.OOO
                    ExternalMessage = $Options.OOO
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
            if (& $Task.Condition) {
                $Batch.Add(@{
                        FunctionName = 'CIPPOffboardingTask'
                        Cmdlet       = $Task.Cmdlet
                        Parameters   = $Task.Parameters
                    })
            }
        }

        if ($Batch.Count -eq 0) {
            Write-LogMessage -API $APIName -tenant $TenantFilter -message "No offboarding tasks selected for user $Username" -sev Warning
            return "No offboarding tasks were selected for $Username"
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

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10 -Compress)
        Write-Information "Started offboarding job for $Username with ID = '$InstanceId'"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Started offboarding job for $Username with $($Batch.Count) tasks. Instance ID: $InstanceId" -sev Info

        return "Offboarding job started for $Username with $($Batch.Count) tasks"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Failed to start offboarding job for $Username : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw $ErrorMessage
    }
}
