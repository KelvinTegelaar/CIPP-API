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
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Starting offboarding orchestration for user $Username" -sev Info

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
                }
            }
            @{
                Condition  = { ![string]::IsNullOrEmpty($Options.OnedriveAccess) }
                Cmdlet     = 'Set-CIPPSharePointPerms'
                Parameters = @{
                    tenantFilter       = $TenantFilter
                    userid             = $Username
                    OnedriveAccessUser = $Options.OnedriveAccess
                    APIName            = $APIName
                }
            }
            @{
                Condition  = { ![string]::IsNullOrEmpty($Options.AccessNoAutomap) }
                Cmdlet     = 'Set-CIPPMailboxAccess'
                Parameters = @{
                    tenantFilter = $TenantFilter
                    userid       = $Username
                    AccessUser   = $Options.AccessNoAutomap
                    Automap      = $false
                    AccessRights = @('FullAccess')
                    APIName      = $APIName
                }
            }
            @{
                Condition  = { ![string]::IsNullOrEmpty($Options.AccessAutomap) }
                Cmdlet     = 'Set-CIPPMailboxAccess'
                Parameters = @{
                    tenantFilter = $TenantFilter
                    userid       = $Username
                    AccessUser   = $Options.AccessAutomap
                    Automap      = $true
                    AccessRights = @('FullAccess')
                    APIName      = $APIName
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
                }
            }
            @{
                Condition  = { $Options.RemoveMFADevices -eq $true }
                Cmdlet     = 'Remove-CIPPUserMFA'
                Parameters = @{
                    UserPrincipalName = $Username
                    TenantFilter      = $TenantFilter
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
            Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "No offboarding tasks selected for user $Username" -sev Warning
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
        if ($TaskInfo) {
            $InputObject | Add-Member -NotePropertyName PostExecution -NotePropertyValue @{
                FunctionName = 'CIPPOffboardingComplete'
                Parameters   = @{
                    TaskInfo     = $TaskInfo
                    TenantFilter = $TenantFilter
                    Username     = $Username
                }
            }
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10 -Compress)
        Write-Information "Started offboarding job for $Username with ID = '$InstanceId'"
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Started offboarding job for $Username with $($Batch.Count) tasks. Instance ID: $InstanceId" -sev Info

        return "Offboarding job started for $Username with $($Batch.Count) tasks"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Offboarding' -tenant $TenantFilter -message "Failed to start offboarding job for $Username : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw $ErrorMessage
    }
}
