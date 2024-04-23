 
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
    $userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($username)" -tenantid $Tenantfilter).id
    $Return = switch ($Options) {
        { $_.'ConvertToShared' -eq 'true' } {
            Set-CIPPMailboxType -ExecutingUser $ExecutingUser -tenantFilter $tenantFilter -userid $username -username $username -MailboxType 'Shared' -APIName $APIName
        }
        { $_.RevokeSessions -eq 'true' } { 
            Revoke-CIPPSessions -tenantFilter $tenantFilter -username $username -userid $userid -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.ResetPass -eq 'true' } { 
            Set-CIPPResetPassword -tenantFilter $tenantFilter -userid $username -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.RemoveGroups -eq 'true' } { 
            Remove-CIPPGroups -userid $userid -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName -Username "$Username"
        }

        { $_.'HideFromGAL' -eq 'true' } {
            Set-CIPPHideFromGAL -tenantFilter $tenantFilter -userid $username -HideFromGAL $true -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.'DisableSignIn' -eq 'true' } {
            Set-CIPPSignInState -TenantFilter $tenantFilter -userid $username -AccountEnabled $false -ExecutingUser $ExecutingUser -APIName $APIName
        }

        { $_.'OnedriveAccess' -ne '' } { 
            $Options.OnedriveAccess | ForEach-Object { Set-CIPPSharePointOwner -tenantFilter $tenantFilter -userid $username -OnedriveAccessUser $_.value -ExecutingUser $ExecutingUser -APIName $APIName }
        }

        { $_.'AccessNoAutomap' -ne '' } { 
            $Options.AccessNoAutomap | ForEach-Object { Set-CIPPMailboxAccess -tenantFilter $tenantFilter -userid $username -AccessUser $_.value -Automap $false -AccessRights @('FullAccess') -ExecutingUser $ExecutingUser -APIName $APIName }
        }
        { $_.'AccessAutomap' -ne '' } { 
            $Options.AccessAutomap | ForEach-Object { Set-CIPPMailboxAccess -tenantFilter $tenantFilter -userid $username -AccessUser $_.value -Automap $true -AccessRights @('FullAccess') -ExecutingUser $ExecutingUser -APIName $APIName }
        }
    
        { $_.'OOO' -ne '' } { 
            Set-CIPPOutOfOffice -tenantFilter $tenantFilter -userid $username -InternalMessage $Options.OOO -ExternalMessage $Options.OOO -ExecutingUser $ExecutingUser -APIName $APIName -state 'Enabled'
        }
        { $_.'forward' -ne '' } { 
            Set-CIPPForwarding -userid $userid -username $username -tenantFilter $Tenantfilter -Forward $Options.forward -KeepCopy [bool]$Options.keepCopy -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.'RemoveLicenses' -eq 'true' } {
            Remove-CIPPLicense -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName
        }

        { $_.'Deleteuser' -eq 'true' } {
            Remove-CIPPUser -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName
        }

        { $_.'RemoveRules' -eq 'true' } {
            Remove-CIPPRules -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName
        }

        { $_.'RemoveMobile' -eq 'true' } {
            Remove-CIPPMobileDevice -userid $userid -username $Username -tenantFilter $Tenantfilter -ExecutingUser $ExecutingUser -APIName $APIName
        }
        { $_.'RemovePermissions' } {
            if ($RunScheduled) {
                Remove-CIPPMailboxPermissions -PermissionsLevel @('FullAccess', 'SendAs', 'SendOnBehalf') -userid 'AllUsers' -AccessUser $UserName -TenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $ExecutingUser

            } else {
                $object = [PSCustomObject]@{
                    TenantFilter  = $tenantFilter
                    User          = $username
                    executingUser = $ExecutingUser
                }
                Push-OutputBinding -Name offboardingmailbox -Value $object
                "Removal of permissions queued. This task will run in the background and send it's results to the logbook."
            }
        }
    
    }
    return $Return

}