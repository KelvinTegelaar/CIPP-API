
function Invoke-CIPPOffboardingJob {
    [CmdletBinding()]
    param (
        [string]$TenantFilter,
        [string]$Username,
        [switch]$RunScheduled,
        $Options,
        $APIName = 'Offboard user',
        $ExecutingUser
    )
    if ($Options -is [string]) {
        $Options = $Options | ConvertFrom-Json
    }
    $userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)?`$select=id" -tenantid $Tenantfilter).id
    Write-Host "Running offboarding job for $username with options: $($Options | ConvertTo-Json -Depth 10)"
    $Return = switch ($Options) {
        { $_.'ConvertToShared' -eq $true } {
            Set-CIPPMailboxType -ExecutingUser $ExecutingUser -tenantFilter $tenantFilter -userid $username -username $username -MailboxType 'Shared' -APIName $APIName
        }
        { $_.RevokeSessions -eq $true } {
            Revoke-CIPPSessions -tenantFilter $tenantFilter -username $username -userid $userid -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.ResetPass -eq $true } {
            Set-CIPPResetPassword -tenantFilter $tenantFilter -userid $username -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.RemoveGroups -eq $true } {
            Remove-CIPPGroups -userid $userid -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName -Username "$Username"
        }

        { $_.'HideFromGAL' -eq $true } {
            Set-CIPPHideFromGAL -tenantFilter $tenantFilter -userid $username -HideFromGAL $true -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.'DisableSignIn' -eq $true } {
            Set-CIPPSignInState -TenantFilter $tenantFilter -userid $username -AccountEnabled $false -ExecutingUser $ExecutingUser -APIName $APIName
        }

        { $_.'OnedriveAccess' } {
            $Options.OnedriveAccess | ForEach-Object { Set-CIPPSharePointPerms -tenantFilter $tenantFilter -userid $username -OnedriveAccessUser $_.value -ExecutingUser $ExecutingUser -APIName $APIName }
        }

        { $_.'AccessNoAutomap' } {
            $Options.AccessNoAutomap | ForEach-Object { Set-CIPPMailboxAccess -tenantFilter $tenantFilter -userid $username -AccessUser $_.value -Automap $false -AccessRights @('FullAccess') -ExecutingUser $ExecutingUser -APIName $APIName }
        }
        { $_.'AccessAutomap' } {
            $Options.AccessAutomap | ForEach-Object { Set-CIPPMailboxAccess -tenantFilter $tenantFilter -userid $username -AccessUser $_.value -Automap $true -AccessRights @('FullAccess') -ExecutingUser $ExecutingUser -APIName $APIName }
        }

        { $_.'OOO' } {
            Set-CIPPOutOfOffice -tenantFilter $tenantFilter -userid $username -InternalMessage $Options.OOO -ExternalMessage $Options.OOO -ExecutingUser $ExecutingUser -APIName $APIName -state 'Enabled'
        }
        { $_.'forward' } {
            if (!$Options.keepCopy) {
                Set-CIPPForwarding -userid $userid -username $username -tenantFilter $Tenantfilter -Forward $Options.forward.value -ExecutingUser $ExecutingUser -APIName $APIName
            } else {
                $KeepCopy = [boolean]$Options.keepCopy
                Set-CIPPForwarding -userid $userid -username $username -tenantFilter $Tenantfilter -Forward $Options.forward.value -KeepCopy $KeepCopy -ExecutingUser $ExecutingUser -APIName $APIName
            }
        }
        { $_.'RemoveLicenses' -eq $true } {
            Remove-CIPPLicense -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName -Schedule
        }

        { $_.'deleteuser' -eq $true } {
            Remove-CIPPUser -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName
        }

        { $_.'removeRules' -eq $true } {
            Write-Host "Removing rules for $username"
            Remove-CIPPMailboxRule -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName -RemoveAllRules
        }

        { $_.'removeMobile' -eq $true } {
            Remove-CIPPMobileDevice -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.'removeCalendarInvites' -eq $true } {
            Remove-CIPPCalendarInvites -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.'removePermissions' } {
            if ($RunScheduled) {
                Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid 'AllUsers' -AccessUser $UserName -TenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $ExecutingUser

            } else {
                $Queue = New-CippQueueEntry -Name "Offboarding - Mailbox Permissions: $Username" -TotalTasks 1
                $InputObject = [PSCustomObject]@{
                    Batch            = @(
                        [PSCustomObject]@{
                            'FunctionName'  = 'ExecOffboardingMailboxPermissions'
                            'TenantFilter'  = $TenantFilter
                            'User'          = $Username
                            'ExecutingUser' = $ExecutingUser
                            'APINAME'       = $APINAME
                            'QueueId'       = $Queue.RowKey
                        }
                    )
                    OrchestratorName = "OffboardingMailboxPermissions_$Username"
                    SkipLog          = $true
                }
                $null = Start-NewOrchestration -FunctionName CIPPOrchestrator -InputObject ($InputObject | ConvertTo-Json -Depth 10)
                "Removal of permissions queued. This task will run in the background and send it's results to the logbook."
            }
        }
        { $_.'RemoveMFADevices' } {
            Remove-CIPPUserMFA -UserPrincipalName $Username -TenantFilter $TenantFilter -ExecutingUser $ExecutingUser
        }

    }
    return $Return

}
