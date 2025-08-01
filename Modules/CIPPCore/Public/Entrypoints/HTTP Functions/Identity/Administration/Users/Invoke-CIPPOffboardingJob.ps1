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
    $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)?`$select=id,displayName" -tenantid $TenantFilter
    $UserID = $User.id
    $DisplayName = $User.displayName
    Write-Host "Running offboarding job for $Username with options: $($Options | ConvertTo-Json -Depth 10)"
    $Return = switch ($Options) {
        { $_.ConvertToShared -eq $true } {
            try {
                Set-CIPPMailboxType -Headers $Headers -tenantFilter $TenantFilter -userid $UserID -username $Username -MailboxType 'Shared' -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.RevokeSessions -eq $true } {
            try {
                Revoke-CIPPSessions -tenantFilter $TenantFilter -username $Username -userid $UserID -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.ResetPass -eq $true } {
            try {
                Set-CIPPResetPassword -tenantFilter $TenantFilter -DisplayName $DisplayName -UserID $username -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.RemoveGroups -eq $true } {
            Remove-CIPPGroups -userid $UserID -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Username $Username
        }
        { $_.HideFromGAL -eq $true } {
            try {
                Set-CIPPHideFromGAL -tenantFilter $TenantFilter -UserID $username -HideFromGAL $true -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.DisableSignIn -eq $true } {
            try {
                Set-CIPPSignInState -TenantFilter $TenantFilter -userid $username -AccountEnabled $false -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.OnedriveAccess } {
            $Options.OnedriveAccess | ForEach-Object {
                try {
                    Set-CIPPSharePointPerms -tenantFilter $TenantFilter -userid $username -OnedriveAccessUser $_.value -Headers $Headers -APIName $APIName
                } catch {
                    $_.Exception.Message
                }
            }
        }
        { $_.AccessNoAutomap } {
            $Options.AccessNoAutomap | ForEach-Object {
                try {
                    Set-CIPPMailboxAccess -tenantFilter $TenantFilter -userid $username -AccessUser $_.value -Automap $false -AccessRights @('FullAccess') -Headers $Headers -APIName $APIName
                } catch {
                    $_.Exception.Message
                }
            }
        }
        { $_.AccessAutomap } {
            $Options.AccessAutomap | ForEach-Object {
                try {
                    Set-CIPPMailboxAccess -tenantFilter $TenantFilter -userid $username -AccessUser $_.value -Automap $true -AccessRights @('FullAccess') -Headers $Headers -APIName $APIName
                } catch {
                    $_.Exception.Message
                }
            }
        }
        { $_.OOO } {
            try {
                Set-CIPPOutOfOffice -tenantFilter $TenantFilter -UserID $username -InternalMessage $Options.OOO -ExternalMessage $Options.OOO -Headers $Headers -APIName $APIName -state 'Enabled'
            } catch {
                $_.Exception.Message
            }
        }
        { $_.forward } {
            if (!$Options.KeepCopy) {
                try {
                    Set-CIPPForwarding -userid $userid -username $username -tenantFilter $TenantFilter -Forward $Options.forward.value -Headers $Headers -APIName $APIName
                } catch {
                    $_.Exception.Message
                }
            } else {
                $KeepCopy = [boolean]$Options.KeepCopy
                try {
                    Set-CIPPForwarding -userid $userid -username $username -tenantFilter $TenantFilter -Forward $Options.forward.value -KeepCopy $KeepCopy -Headers $Headers -APIName $APIName
                } catch {
                    $_.Exception.Message
                }
            }
        }
        { $_.disableForwarding } {
            try {
                Set-CIPPForwarding -userid $userid -username $username -tenantFilter $TenantFilter -Disable $true -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.RemoveLicenses -eq $true } {
            Remove-CIPPLicense -userid $userid -username $Username -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Schedule
        }
        { $_.DeleteUser -eq $true } {
            try {
                Remove-CIPPUser -UserID $userid -Username $Username -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.RemoveRules -eq $true } {
            Write-Host "Removing rules for $username"
            try {
                Remove-CIPPMailboxRule -userid $userid -username $Username -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName -RemoveAllRules
            } catch {
                $_.Exception.Message
            }
        }
        { $_.RemoveMobile -eq $true } {
            try {
                Remove-CIPPMobileDevice -userid $userid -username $Username -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.removeCalendarInvites -eq $true } {
            try {
                Remove-CIPPCalendarInvites -UserID $userid -Username $Username -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
        { $_.removePermissions } {
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
        { $_.RemoveMFADevices -eq $true } {
            try {
                Remove-CIPPUserMFA -UserPrincipalName $Username -TenantFilter $TenantFilter -Headers $Headers
            } catch {
                $_.Exception.Message
            }
        }
        { $_.ClearImmutableId -eq $true } {
            try {
                Clear-CIPPImmutableID -UserID $userid -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
            } catch {
                $_.Exception.Message
            }
        }
    }
    return $Return

}
