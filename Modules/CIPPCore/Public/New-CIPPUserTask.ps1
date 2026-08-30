function New-CIPPUserTask {
    [CmdletBinding()]
    param (
        $UserObj,
        $APIName = 'New User Task',
        $TenantFilter,
        $Headers
    )
    $Results = [System.Collections.Generic.List[string]]::new()

    try {
        $CreationResults = New-CIPPUser -UserObj $UserObj -APIName $APIName -Headers $Headers
        $Results.Add('Created New User.')
        $Results.Add("Username: $($CreationResults.Username)")
        $Results.Add("Password: $($CreationResults.Password)")
    } catch {
        $Results.Add("$($_.Exception.Message)" )
        throw @{'Results' = $Results }
    }

    try {
        if ($UserObj.licenses.value) {
            if ($UserObj.sherwebLicense.value) {
                $null = Set-SherwebSubscription -Headers $Headers -TenantFilter $UserObj.tenantFilter -SKU $UserObj.sherwebLicense.value -Add 1
                $null = $Results.Add('Added Sherweb License, scheduling assignment')
                $taskObject = [PSCustomObject]@{
                    TenantFilter  = $UserObj.tenantFilter
                    Name          = "Assign License: $UserPrincipalName"
                    Command       = @{
                        value = 'Set-CIPPUserLicense'
                    }
                    Parameters    = [pscustomobject]@{
                        UserId      = $CreationResults.Username
                        APIName     = 'Sherweb License Assignment'
                        AddLicenses = $UserObj.licenses.value
                    }
                    ScheduledTime = 0 #right now, which is in the next 15 minutes and should cover most cases.
                    PostExecution = @{
                        Webhook = [bool]$Request.Body.PostExecution.webhook
                        Email   = [bool]$Request.Body.PostExecution.email
                        PSA     = [bool]$Request.Body.PostExecution.psa
                    }
                }
                Add-CIPPScheduledTask -Task $taskObject -hidden $false -Headers $Headers
            } else {
                $LicenseResults = Set-CIPPUserLicense -UserId $CreationResults.Username -TenantFilter $UserObj.tenantFilter -AddLicenses $UserObj.licenses.value -Headers $Headers
                $Results.Add($LicenseResults)
            }
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant $($UserObj.tenantFilter) -message "Failed to assign the license. Error:$($_.Exception.Message)" -Sev 'Error'
        $Results.Add("Failed to assign the license. $($_.Exception.Message)")
    }

    try {
        if ($UserObj.AddedAliases) {
            $AliasResults = Add-CIPPAlias -User $CreationResults.Username -Aliases ($UserObj.AddedAliases -split '\s') -UserPrincipalName $CreationResults.Username -TenantFilter $UserObj.tenantFilter -APIName $APIName -Headers $Headers
            $Results.Add($AliasResults)
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant $($UserObj.tenantFilter) -message "Failed to create the Aliases. Error:$($_.Exception.Message)" -Sev 'Error'
        $Results.Add("Failed to create the Aliases: $($_.Exception.Message)")
    }
    if ($UserObj.copyFrom.value) {
        Write-Host "Copying from $($UserObj.copyFrom.value)"
        $CopyFrom = Set-CIPPCopyGroupMembers -Headers $Headers -CopyFromId $UserObj.copyFrom.value -UserID $CreationResults.Username -TenantFilter $UserObj.tenantFilter
        $CopyFrom.Success | ForEach-Object { $Results.Add($_) }
        $CopyFrom.Error | ForEach-Object { $Results.Add($_) }
        # Groups deliberately left out (dynamic, AD-synced, public, already assigned) are reported
        # too: silently dropping them reads as the copy having missed something.
        $CopyFrom.Skipped | ForEach-Object { $Results.Add($_) }
    }

    # Add to groups
    if ($UserObj.AddToGroups) {
        $ExoGroupTypes = @('Distribution list', 'Mail-Enabled Security')
        $UserObj.AddToGroups | ForEach-Object {
            $Group = $_
            $GroupType = $Group.addedFields.groupType
            try {
                $AddMemberResult = Add-CIPPGroupMember -Headers $Headers -GroupType $GroupType -GroupId $Group.value -Member @($CreationResults.Username) -TenantFilter $UserObj.tenantFilter
                $Results.Add($AddMemberResult)
            } catch {
                # EXO group adds frequently fail right after user creation due to Exchange directory replication lag.
                # Schedule a delayed retry so the user lands in the group automatically once EXO sees the recipient.
                # Groups selected from a template often carry no type at all (older templates stored only a label
                # and a value), and an untyped group is just as likely to be a distribution list as anything else,
                # so treat unknown the same as Exchange rather than failing the onboarding outright.
                if (-not $GroupType -or $GroupType -in $ExoGroupTypes) {
                    try {
                        $TaskBody = [PSCustomObject]@{
                            TenantFilter  = $UserObj.tenantFilter
                            Name          = "Retry Add Group Member: $($CreationResults.Username) -> $($Group.label)"
                            Command       = @{ value = 'Add-CIPPGroupMember' }
                            Parameters    = [PSCustomObject]@{
                                GroupType    = $GroupType
                                GroupId      = $Group.value
                                Member       = @($CreationResults.Username)
                                TenantFilter = $UserObj.tenantFilter
                                APIName      = 'Add Group Member (Retry)'
                            }
                            ScheduledTime = [int64](([datetime]::UtcNow).AddMinutes(15) - (Get-Date '1/1/1970')).TotalSeconds
                            PostExecution = @{ Webhook = $false; Email = $false; PSA = $false }
                        }
                        $null = Add-CIPPScheduledTask -Task $TaskBody -hidden $false -Headers $Headers -DisallowDuplicateName $true
                        $Results.Add("Could not add $($CreationResults.Username) to $($Group.label) yet (Exchange replication delay). A retry has been scheduled in 15 minutes.")
                    } catch {
                        $Results.Add("Failed to add to group $($Group.label): $_")
                    }
                } else {
                    $Results.Add("Failed to add to group $($Group.label): $_")
                }
            }
        }
    }

    # Give the user access to the tenant's shared calendars and shared mailboxes. Both are always
    # scheduled instead of run inline: a freshly created user is not a usable Exchange recipient for
    # several minutes, so Add-MailboxFolderPermission / Add-MailboxPermission would fail right now.
    if ($UserObj.sharedCalendars -or $UserObj.sharedMailboxes) {
        # This endpoint only grants Identity.User.ReadWrite, so the request must not be able to hand
        # the new account access to an arbitrary person's calendar or mailbox. Resolve the tenant's
        # shared mailboxes up front and refuse anything else (fail closed when the lookup errors).
        try {
            $TenantSharedMailboxes = New-ExoRequest -tenantid $UserObj.tenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ RecipientTypeDetails = 'SharedMailbox' } -Select 'UserPrincipalName,PrimarySmtpAddress'
            $AllowedSharedMailboxes = @(@($TenantSharedMailboxes.UserPrincipalName) + @($TenantSharedMailboxes.PrimarySmtpAddress) | Where-Object { $_ })
        } catch {
            $AllowedSharedMailboxes = $null
            $Results.Add("Could not verify the shared mailboxes for this tenant, no shared access was granted: $($_.Exception.Message)")
        }

        if ($null -ne $AllowedSharedMailboxes) {
            # ponytail: single attempt. Exchange usually has the recipient within 15 minutes; if
            # provisioning is slower the task fails visibly in the scheduler. Upgrade path is a
            # bounded retry on recipient-not-found.
            $SharedAccessTime = [int64](([datetime]::UtcNow).AddMinutes(15) - (Get-Date '1/1/1970')).TotalSeconds
            $SharedAccessGrants = [System.Collections.Generic.List[object]]::new()

            $CalendarPermission = if ($UserObj.sharedCalendarPermission.value) { $UserObj.sharedCalendarPermission.value } elseif ($UserObj.sharedCalendarPermission) { $UserObj.sharedCalendarPermission } else { 'Editor' }
            foreach ($Calendar in @($UserObj.sharedCalendars)) {
                $CalendarId = if ($Calendar.value) { $Calendar.value } else { $Calendar }
                $CalendarLabel = if ($Calendar.label) { $Calendar.label } else { $CalendarId }
                $SharedAccessGrants.Add([PSCustomObject]@{
                        Identity   = $CalendarId
                        Kind       = 'calendar'
                        Label      = $CalendarLabel
                        Name       = "Grant Calendar Access: $($CreationResults.Username) -> $CalendarId"
                        Command    = 'Set-CIPPCalendarPermission'
                        Parameters = [PSCustomObject]@{
                            TenantFilter           = $UserObj.tenantFilter
                            UserID                 = $CalendarId
                            UserToGetPermissions   = $CreationResults.Username
                            FolderName             = 'Calendar'
                            AutoResolveFolderName  = $true
                            Permissions            = $CalendarPermission
                            SendNotificationToUser = $true
                            APIName                = 'Shared Calendar Onboarding'
                        }
                        Success    = "Scheduled $CalendarPermission access to the calendar of $CalendarLabel in 15 minutes. A sharing invitation will be sent to $($CreationResults.Username) once Exchange has provisioned the mailbox."
                    })
            }

            # Set-CIPPMailboxPermission takes a single level, so Full Access plus Send As means one
            # task per level. They are separate Exchange operations anyway.
            $MailboxPermissions = @(@($UserObj.sharedMailboxPermission) | ForEach-Object { if ($_.value) { $_.value } else { $_ } } | Where-Object { $_ })
            if (-not $MailboxPermissions) { $MailboxPermissions = @('FullAccess') }
            foreach ($Mailbox in @($UserObj.sharedMailboxes)) {
                $MailboxId = if ($Mailbox.value) { $Mailbox.value } else { $Mailbox }
                $MailboxLabel = if ($Mailbox.label) { $Mailbox.label } else { $MailboxId }
                foreach ($MailboxPermission in $MailboxPermissions) {
                    # AutoMap only applies to FullAccess, and is what makes Outlook mount the mailbox
                    # on its own, so no invitation is needed on this side of the feature.
                    $AutoMapNote = if ($MailboxPermission -eq 'FullAccess') { ' Outlook adds the mailbox automatically.' } else { '' }
                    $SharedAccessGrants.Add([PSCustomObject]@{
                            Identity   = $MailboxId
                            Kind       = 'mailbox'
                            Label      = $MailboxLabel
                            Name       = "Grant Mailbox Access: $($CreationResults.Username) -> $MailboxId ($MailboxPermission)"
                            Command    = 'Set-CIPPMailboxPermission'
                            Parameters = [PSCustomObject]@{
                                TenantFilter    = $UserObj.tenantFilter
                                UserId          = $MailboxId
                                AccessUser      = $CreationResults.Username
                                PermissionLevel = $MailboxPermission
                                Action          = 'Add'
                                AutoMap         = $true
                                APIName         = 'Shared Mailbox Onboarding'
                            }
                            Success    = "Scheduled $MailboxPermission on the shared mailbox $MailboxLabel in 15 minutes.$AutoMapNote"
                        })
                }
            }

            foreach ($Grant in $SharedAccessGrants) {
                if ($AllowedSharedMailboxes -notcontains $Grant.Identity) {
                    $Results.Add("Skipped $($Grant.Kind) access to $($Grant.Label): it is not a shared mailbox in this tenant.")
                    continue
                }
                try {
                    $TaskBody = [PSCustomObject]@{
                        TenantFilter  = $UserObj.tenantFilter
                        Name          = $Grant.Name
                        Command       = @{ value = $Grant.Command }
                        Parameters    = $Grant.Parameters
                        ScheduledTime = $SharedAccessTime
                        PostExecution = @{ Webhook = $false; Email = $false; PSA = $false }
                    }
                    # Add-CIPPScheduledTask reports most failures by returning an error string, only
                    # table write failures throw, so the return value decides what we tell the caller.
                    $ScheduleResult = Add-CIPPScheduledTask -Task $TaskBody -hidden $false -Headers $Headers -DisallowDuplicateName $true
                    if ($ScheduleResult -like 'Successfully added task:*') {
                        $Results.Add($Grant.Success)
                    } else {
                        $Results.Add("Failed to schedule $($Grant.Kind) access to $($Grant.Label): $ScheduleResult")
                    }
                } catch {
                    $Results.Add("Failed to schedule $($Grant.Kind) access to $($Grant.Label): $($_.Exception.Message)")
                }
            }
        }
    }

    if ($UserObj.setManager) {
        $ManagerResults = Set-CIPPManager -Users $CreationResults.Username -Manager $UserObj.setManager.value -TenantFilter $UserObj.tenantFilter -Headers $Headers
        $Results.Add($ManagerResults.Result)
    }

    if ($UserObj.setSponsor) {
        $SponsorResults = Set-CIPPSponsor -Users $CreationResults.Username -Sponsor $UserObj.setSponsor.value -TenantFilter $UserObj.tenantFilter -Headers $Headers
        $Results.Add($SponsorResults.Result)
    }

    try {
        if ($UserObj.perUserMfa -eq $true) {
            $MfaResult = Set-CIPPPerUserMFA -TenantFilter $UserObj.tenantFilter -userId $CreationResults.Username -State 'enforced' -Headers $Headers -APIName $APIName
            $Results.Add($MfaResult)
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant $($UserObj.tenantFilter) -message "Failed to set per-user MFA. Error:$($_.Exception.Message)" -Sev 'Error'
        $Results.Add("Failed to set per-user MFA: $($_.Exception.Message)")
    }

    return @{
        Results  = $Results
        Username = $CreationResults.Username
        Password = $CreationResults.Password
        CopyFrom = $CopyFrom
        User     = $CreationResults.User
    }
}
