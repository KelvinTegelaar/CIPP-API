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
    $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)?`$select=id,displayName,onPremisesSyncEnabled,onPremisesImmutableId" -tenantid $TenantFilter
    $UserID = $User.id
    $DisplayName = $User.displayName
    Write-Host "Running offboarding job for $Username with options: $($Options | ConvertTo-Json -Depth 10)"
    $JobResults = [ordered]@{}

    switch ($Options) {
        { $_.ConvertToShared -eq $true } {
            try {
                $Result = Set-CIPPMailboxType -Headers $Headers -tenantFilter $TenantFilter -userid $UserID -username $Username -MailboxType 'Shared' -APIName $APIName
                $JobResults['ConvertToSharedMailbox'] = $Result
            }
            catch {
                $JobResults['ConvertToSharedMailbox'] = $_.Exception.Message
            }
        }
        { $_.RevokeSessions -eq $true } {
            try {
                $Result = Revoke-CIPPSessions -tenantFilter $TenantFilter -username $Username -userid $UserID -Headers $Headers -APIName $APIName
                $JobResults['RevokeSessions'] = $Result
            }
            catch {
                $JobResults['RevokeSessions'] = $_.Exception.Message
            }
        }
        { $_.ResetPass -eq $true } {
            try {
                $Result = Set-CIPPResetPassword -tenantFilter $TenantFilter -DisplayName $DisplayName -UserID $username -Headers $Headers -APIName $APIName
                $JobResults['ResetPassword'] = $Result
            }
            catch {
                $JobResults['ResetPassword'] = $_.Exception.Message
            }
        }
        { $_.RemoveGroups -eq $true } {
            try {
                $Result = Remove-CIPPGroups -userid $UserID -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Username $Username
                if ($Result -is [array]) {
                    $JobResults['RemoveGroups'] = $Result | ForEach-Object { [PSCustomObject]@{ Result = $_ } }
                }
                elseif ($Result) {
                    $JobResults['RemoveGroups'] = @([PSCustomObject]@{ Result = $Result })
                }
                else {
                    $JobResults['RemoveGroups'] = "User $Username is not a member of any groups"
                }
            }
            catch {
                $JobResults['RemoveGroups'] = @([PSCustomObject]@{ Result = $_.Exception.Message })
            }
        }
        { $_.HideFromGAL -eq $true } {
            try {
                $Result = Set-CIPPHideFromGAL -tenantFilter $TenantFilter -UserID $username -HideFromGAL $true -Headers $Headers -APIName $APIName
                $JobResults['HideFromGAL'] = $Result
            }
            catch {
                $JobResults['HideFromGAL'] = $_.Exception.Message
            }
        }
        { $_.DisableSignIn -eq $true } {
            try {
                $Result = Set-CIPPSignInState -TenantFilter $TenantFilter -userid $username -AccountEnabled $false -Headers $Headers -APIName $APIName
                $JobResults['DisableSignIn'] = $Result
            }
            catch {
                $JobResults['DisableSignIn'] = $_.Exception.Message
            }
        }
        { $_.OnedriveAccess } {
            $JobResults['OnedriveAccess'] = [System.Collections.Generic.List[PSCustomObject]]::new()
            $Options.OnedriveAccess | ForEach-Object {
                try {
                    $Result = Set-CIPPSharePointPerms -tenantFilter $TenantFilter -userid $username -OnedriveAccessUser $_.value -Headers $Headers -APIName $APIName
                    $JobResults['OnedriveAccess'].Add([PSCustomObject]@{ Result = $Result })
                }
                catch {
                    $JobResults['OnedriveAccess'].Add([PSCustomObject]@{ Result = $_.Exception.Message })
                }
            }
        }
        { $_.AccessNoAutomap } {
            $JobResults['AccessNoAutomap'] = [System.Collections.Generic.List[PSCustomObject]]::new()
            $Options.AccessNoAutomap | ForEach-Object {
                try {
                    $Result = Set-CIPPMailboxAccess -tenantFilter $TenantFilter -userid $username -AccessUser $_.value -Automap $false -AccessRights @('FullAccess') -Headers $Headers -APIName $APIName
                    $JobResults['AccessNoAutomap'].Add([PSCustomObject]@{ Result = $Result })
                }
                catch {
                    $JobResults['AccessNoAutomap'].Add([PSCustomObject]@{ Result = $_.Exception.Message })
                }
            }
        }
        { $_.AccessAutomap } {
            $JobResults['AccessAutomap'] = [System.Collections.Generic.List[PSCustomObject]]::new()
            $Options.AccessAutomap | ForEach-Object {
                try {
                    $Result = Set-CIPPMailboxAccess -tenantFilter $TenantFilter -userid $username -AccessUser $_.value -Automap $true -AccessRights @('FullAccess') -Headers $Headers -APIName $APIName
                    $JobResults['AccessAutomap'].Add([PSCustomObject]@{ Result = $Result })
                }
                catch {
                    $JobResults['AccessAutomap'].Add([PSCustomObject]@{ Result = $_.Exception.Message })
                }
            }
        }
        { $_.OOO } {
            try {
                $Result = Set-CIPPOutOfOffice -tenantFilter $TenantFilter -UserID $username -InternalMessage $Options.OOO -ExternalMessage $Options.OOO -Headers $Headers -APIName $APIName -state 'Enabled'
                $JobResults['SetOutOfOffice'] = $Result
            }
            catch {
                $JobResults['SetOutOfOffice'] = $_.Exception.Message
            }
        }
        { $_.forward } {
            if (!$Options.KeepCopy) {
                try {
                    $Result = Set-CIPPForwarding -userid $userid -username $username -tenantFilter $TenantFilter -Forward $Options.forward.value -Headers $Headers -APIName $APIName
                    $JobResults['SetForwarding'] = $Result
                }
                catch {
                    $JobResults['SetForwarding'] = $_.Exception.Message
                }
            }
            else {
                $KeepCopy = [boolean]$Options.KeepCopy
                try {
                    $Result = Set-CIPPForwarding -userid $userid -username $username -tenantFilter $TenantFilter -Forward $Options.forward.value -KeepCopy $KeepCopy -Headers $Headers -APIName $APIName
                    $JobResults['SetForwarding'] = $Result
                }
                catch {
                    $JobResults['SetForwarding'] = $_.Exception.Message
                }
            }
        }
        { $_.disableForwarding } {
            try {
                $Result = Set-CIPPForwarding -userid $userid -username $username -tenantFilter $TenantFilter -Disable $true -Headers $Headers -APIName $APIName
                $JobResults['DisableForwarding'] = $Result
            }
            catch {
                $JobResults['DisableForwarding'] = $_.Exception.Message
            }
        }
        { $_.RemoveTeamsPhoneDID } {
            try {
                $Result = Remove-CIPPUserTeamsPhoneDIDs -userid $userid -username $username -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                $JobResults['RemoveTeamsPhoneDID'] = $Result
            }
            catch {
                $JobResults['RemoveTeamsPhoneDID'] = $_.Exception.Message
            }
        }
        { $_.RemoveLicenses -eq $true } {
            try {
                $Result = Remove-CIPPLicense -userid $userid -username $Username -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Schedule
                if ($Result -is [array]) {
                    $JobResults['RemoveLicenses'] = $Result | ForEach-Object { [PSCustomObject]@{ Result = $_ } }
                }
                elseif ($Result) {
                    $JobResults['RemoveLicenses'] = @([PSCustomObject]@{ Result = $Result })
                }
                else {
                    $JobResults['RemoveLicenses'] = "No licenses found to remove for $Username"
                }
            }
            catch {
                $JobResults['RemoveLicenses'] = @([PSCustomObject]@{ Result = $_.Exception.Message })
            }
        }
        { $_.DeleteUser -eq $true } {
            try {
                $Result = Remove-CIPPUser -UserID $userid -Username $Username -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                $JobResults['DeleteUser'] = $Result
            }
            catch {
                $JobResults['DeleteUser'] = $_.Exception.Message
            }
        }
        { $_.RemoveRules -eq $true } {
            Write-Host "Removing rules for $username"
            try {
                $Result = Remove-CIPPMailboxRule -userid $userid -username $Username -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName -RemoveAllRules
                $JobResults['RemoveRules'] = $Result
            }
            catch {
                $JobResults['RemoveRules'] = $_.Exception.Message
            }
        }
        { $_.RemoveMobile -eq $true } {
            try {
                $Result = Remove-CIPPMobileDevice -userid $userid -username $Username -tenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                $JobResults['RemoveMobile'] = $Result
            }
            catch {
                $JobResults['RemoveMobile'] = $_.Exception.Message
            }
        }
        { $_.removeCalendarInvites -eq $true } {
            try {
                $Result = Remove-CIPPCalendarInvites -UserID $userid -Username $Username -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                $JobResults['RemoveCalendarInvites'] = $Result
            }
            catch {
                $JobResults['RemoveCalendarInvites'] = $_.Exception.Message
            }
        }
        { $_.removePermissions } {
            if ($RunScheduled) {
                try {
                    $Result = Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid 'AllUsers' -AccessUser $UserName -TenantFilter $TenantFilter -APIName $APINAME -Headers $Headers
                    if ($Result -is [array]) {
                        $JobResults['RemovePermissions'] = $Result | ForEach-Object { [PSCustomObject]@{ Result = $_ } }
                    }
                    elseif ($Result) {
                        $JobResults['RemovePermissions'] = @([PSCustomObject]@{ Result = $Result })
                    }
                    else {
                        $JobResults['RemovePermissions'] = "No mailbox permissions found to remove for $UserName"
                    }
                }
                catch {
                    if ($_.Exception.Message -is [array]) {
                        $JobResults['RemovePermissions'] = $_.Exception.Message | ForEach-Object { [PSCustomObject]@{ Result = $_ } }
                    }
                    else {
                        $JobResults['RemovePermissions'] = @([PSCustomObject]@{ Result = $_.Exception.Message })
                    }
                }

            }
            else {
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
                $Result = "Removal of permissions queued. This task will run in the background and send it's results to the logbook."
                $JobResults['RemovePermissions'] = $Result
            }
        }
        { $_.RemoveMFADevices -eq $true } {
            try {
                $Result = Remove-CIPPUserMFA -UserPrincipalName $Username -TenantFilter $TenantFilter -Headers $Headers
                $JobResults['RemoveMFADevices'] = $Result
            }
            catch {
                $JobResults['RemoveMFADevices'] = $_.Exception.Message
            }
        }
        { $_.ClearImmutableId -eq $true } {
            if ($User.onPremisesSyncEnabled -ne $true -and ![string]::IsNullOrEmpty($User.onPremisesImmutableId)) {
                Write-LogMessage -Message "User $Username has an ImmutableID set but is not synced from on-premises. Proceeding to clear the ImmutableID." -TenantFilter $TenantFilter -Severity 'Warning' -APIName $APIName -Headers $Headers
                try {
                    $Result = Clear-CIPPImmutableID -UserID $userid -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                    $JobResults['ClearImmutableId'] = $Result
                }
                catch {
                    $JobResults['ClearImmutableId'] = $_.Exception.Message
                }
            }
            elseif ($User.onPremisesSyncEnabled -eq $true -and ![string]::IsNullOrEmpty($User.onPremisesImmutableId)) {
                Write-LogMessage -Message "User $Username is synced from on-premises. Scheduling an Immutable ID clear for when the user account has been soft deleted." -TenantFilter $TenantFilter -Severity 'Error' -APIName $APIName -Headers $Headers
                $Result = 'Scheduling Immutable ID clear task for when the user account is no longer synced in the on-premises directory.'
                $ScheduledTask = @{
                    TenantFilter  = $TenantFilter
                    Name          = "Clear Immutable ID: $Username"
                    Command       = @{
                        value = 'Clear-CIPPImmutableID'
                    }
                    Parameters    = [pscustomobject]@{
                        userid  = $userid
                        APIName = $APIName
                        Headers = $Headers
                    }
                    Trigger       = @{
                        Type               = 'DeltaQuery'
                        DeltaResource      = 'users'
                        ResourceFilter     = @($UserID)
                        EventType          = 'deleted'
                        UseConditions      = $false
                        ExecutePerResource = $true
                        ExecutionMode      = 'once'
                    }
                    ScheduledTime = [int64](([datetime]::UtcNow).AddMinutes(5) - (Get-Date '1/1/1970')).TotalSeconds
                    Recurrence    = '15m'
                    PostExecution = @{
                        Webhook = $false
                        Email   = $false
                        PSA     = $false
                    }
                }
                Add-CIPPScheduledTask -Task $ScheduledTask -hidden $false
                $JobResults['ClearImmutableId'] = $Result
            }
        }
    }
    return [PSCustomObject]$JobResults

}
```
