
function Invoke-CIPPOffboardingJob {
    [CmdletBinding()]
    param (
        [string]$TenantFilter,
        [string]$Username,
        [switch]$RunScheduled,
        $Options,
        $APIName = 'Offboard user',
        $Headers
    )
    if ($Options -is [string]) {
        $Options = $Options | ConvertFrom-Json
    }
    $userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)?`$select=id" -tenantid $Tenantfilter).id
    Write-Host "Running offboarding job for $username with options: $($Options | ConvertTo-Json -Depth 10)"
    $Return = switch ($Options) {
        { $_.'ConvertToShared' -eq $true } {
            Set-CIPPMailboxType -Headers $Headers -tenantFilter $tenantFilter -userid $username -username $username -MailboxType 'Shared' -APIName $APIName
        }
        { $_.RevokeSessions -eq $true } {
            Revoke-CIPPSessions -tenantFilter $tenantFilter -username $username -userid $userid -Headers $Headers -APIName $APIName
        }
        { $_.ResetPass -eq $true } {
            Set-CIPPResetPassword -tenantFilter $tenantFilter -UserID $username -Headers $Headers -APIName $APIName
        }
        { $_.RemoveGroups -eq $true } {
            Remove-CIPPGroups -userid $userid -tenantFilter $Tenantfilter -Headers $Headers -APIName $APIName -Username "$Username"
        }
        { $_.'HideFromGAL' -eq $true } {
            Set-CIPPHideFromGAL -tenantFilter $tenantFilter -UserID $username -hidefromgal $true -Headers $Headers -APIName $APIName
        }
        { $_.'DisableSignIn' -eq $true } {
            Set-CIPPSignInState -TenantFilter $tenantFilter -userid $username -AccountEnabled $false -Headers $Headers -APIName $APIName
        }
        { $_.'OnedriveAccess' } {
            $Options.OnedriveAccess | ForEach-Object { Set-CIPPSharePointPerms -tenantFilter $tenantFilter -userid $username -OnedriveAccessUser $_.value -Headers $Headers -APIName $APIName }
        }
        { $_.'AccessNoAutomap' } {
            $Options.AccessNoAutomap | ForEach-Object { Set-CIPPMailboxAccess -tenantFilter $tenantFilter -userid $username -AccessUser $_.value -Automap $false -AccessRights @('FullAccess') -Headers $Headers -APIName $APIName }
        }
        { $_.'AccessAutomap' } {
            $Options.AccessAutomap | ForEach-Object { Set-CIPPMailboxAccess -tenantFilter $tenantFilter -userid $username -AccessUser $_.value -Automap $true -AccessRights @('FullAccess') -Headers $Headers -APIName $APIName }
        }
        { $_.'OOO' } {
            Set-CIPPOutOfOffice -tenantFilter $tenantFilter -userid $username -InternalMessage $Options.OOO -ExternalMessage $Options.OOO -Headers $Headers -APIName $APIName -state 'Enabled'
        }
        { $_.'forward' } {
            if (!$Options.keepCopy) {
                Set-CIPPForwarding -userid $userid -username $username -tenantFilter $Tenantfilter -Forward $Options.forward.value -Headers $Headers -APIName $APIName
            } else {
                $KeepCopy = [boolean]$Options.keepCopy
                Set-CIPPForwarding -userid $userid -username $username -tenantFilter $Tenantfilter -Forward $Options.forward.value -KeepCopy $KeepCopy -Headers $Headers -APIName $APIName
            }
        }
        { $_.'RemoveLicenses' -eq $true } {
            Remove-CIPPLicense -userid $userid -username $Username -tenantFilter $Tenantfilter -Headers $Headers -APIName $APIName -Schedule
        }
        { $_.'deleteuser' -eq $true } {
            Remove-CIPPUser -userid $userid -username $Username -tenantFilter $Tenantfilter -Headers $Headers -APIName $APIName
        }
        { $_.'removeRules' -eq $true } {
            Write-Host "Removing rules for $username"
            Remove-CIPPMailboxRule -userid $userid -username $Username -tenantFilter $Tenantfilter -Headers $Headers -APIName $APIName -RemoveAllRules
        }
        { $_.'removeMobile' -eq $true } {
            Remove-CIPPMobileDevice -userid $userid -username $Username -tenantFilter $Tenantfilter -Headers $Headers -APIName $APIName
        }
        { $_.'removeCalendarInvites' -eq $true } {
            Remove-CIPPCalendarInvites -userid $userid -username $Username -tenantFilter $Tenantfilter -Headers $Headers -APIName $APIName
        }
        { $_.'removePermissions' } {
            if ($RunScheduled) {
                Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid 'AllUsers' -AccessUser $UserName -TenantFilter $TenantFilter -APIName $APINAME -Headers $Headers

            } else {
                $Queue = New-CippQueueEntry -Name "Offboarding - Mailbox Permissions: $Username" -TotalTasks 1
                $InputObject = [PSCustomObject]@{
                    Batch            = @(
                        [PSCustomObject]@{
                            'FunctionName' = 'ExecOffboardingMailboxPermissions'
                            'TenantFilter' = $TenantFilter
                            'User'         = $Username
                            'Headers'      = $Headers
                            'APINAME'      = $APINAME
                            'QueueId'      = $Queue.RowKey
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
            Remove-CIPPUserMFA -UserPrincipalName $Username -TenantFilter $TenantFilter -Headers $Headers
        }
        { $_.'ClearImmutableId' -eq $true } {
            Clear-CIPPImmutableId -userid $userid -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
        }
    }
    return $Return

}
