function Invoke-CIPPOnboardingJob {
    <#
    .SYNOPSIS
        Runs the fixes picked in the user onboarding wizard for one returning user.
    .DESCRIPTION
        Runs as a scheduled task queued by ExecOnboardUser. Options.Fixes lists the fixes as
        { Key, Params }; repeated keys are merged and the steps run one after another in a fixed
        order, each reporting to its own step of the live-progress row. A failed step is reported and
        the rest still run. Every step changes only the onboarded user's own account, mailbox,
        calendar or OneDrive, and admin roles are never assigned.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [string]$TenantFilter,
        [string]$Username,
        $Options,
        $APIName = 'User Onboarding',
        $Headers,
        $TaskInfo,
        # Live-progress job created by the caller; when set, the user's status row is kept up to date
        [string]$DeploymentId,
        # Zero-based indices of the steps to run again (a step re-run); empty runs every requested step
        [int[]]$StepIndexes = @()
    )

    try {
        # The scheduler hands stored parameters over as hashtables; plain objects read the same either way.
        $Options = if ($Options -is [string]) { $Options | ConvertFrom-Json } else { $Options | ConvertTo-Json -Depth 10 | ConvertFrom-Json }

        # Merge repeated keys into one set of parameters per step.
        $Requested = @{}
        foreach ($Fix in @($Options.Fixes | Where-Object { $_ })) {
            $Key = [string]$Fix.Key
            if (-not $Requested.ContainsKey($Key)) {
                $Requested[$Key] = @{
                    Items     = [System.Collections.Generic.List[object]]::new()
                    Licenses  = [System.Collections.Generic.List[string]]::new()
                    ManagerId = $null
                    UserId    = $null
                    Locale    = $null
                    TimeZone  = $null
                }
            }
            foreach ($Item in @($Fix.Params.Items | Where-Object { $_ })) { $Requested[$Key].Items.Add($Item) }
            foreach ($License in @($Fix.Params.Licenses | Where-Object { $_ })) {
                if (-not $Requested[$Key].Licenses.Contains([string]$License)) { $Requested[$Key].Licenses.Add([string]$License) }
            }
            if ($Fix.Params.ManagerId) { $Requested[$Key].ManagerId = [string]($Fix.Params.ManagerId.value ?? $Fix.Params.ManagerId) }
            if ($Fix.Params.UserId) { $Requested[$Key].UserId = [string]($Fix.Params.UserId.value ?? $Fix.Params.UserId) }
            if ($Fix.Params.Locale) { $Requested[$Key].Locale = [string]($Fix.Params.Locale.value ?? $Fix.Params.Locale) }
            if ($Fix.Params.TimeZone) { $Requested[$Key].TimeZone = [string]($Fix.Params.TimeZone.value ?? $Fix.Params.TimeZone) }
        }

        # A shortcut needs the OneDrive to exist, so pre-provisioning always runs ahead of it.
        if ($Requested.ContainsKey('AddOneDriveShortcuts') -and -not $Requested.ContainsKey('ProvisionOneDrive')) { $Requested['ProvisionOneDrive'] = @{} }

        # Set by the scheduler for a task queued by a caller without Identity.PrivilegedUser.ReadWrite.
        $PrivilegedRestricted = [bool]($script:CippPrivilegedUserRestrictedStorage -and $script:CippPrivilegedUserRestrictedStorage.Value)
        $GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        # An object id or a UPN; the value is placed in a Graph path and may not carry a text replacement variable.
        $UserPattern = "^[^\s/\\?#%&']+$"
        $CalendarRoles = 'Owner', 'PublishingEditor', 'Editor', 'PublishingAuthor', 'Author', 'NonEditingAuthor', 'Reviewer', 'Contributor', 'LimitedDetails', 'AvailabilityOnly'
        $SharePointUrlPattern = '^https://[a-z0-9-]+\.sharepoint(-mil)?\.(com|us|cn|de)/'

        # Steps in execution order. Keep the keys in sync with the allowlist in Invoke-ExecOnboardUser.
        # $P is the step's merged parameters, $Upn and $UserObjectId the onboarded user.
        $StepOrder = @(
            @{
                Key   = 'EnableSignIn'
                Title = 'Enable sign-in'
                Run   = { Set-CIPPSignInState -UserID $Upn -AccountEnabled $true -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers }
            }
            @{
                Key   = 'AssignLicenses'
                Title = 'Assign licences'
                Run   = {
                    $Invalid = @($P.Licenses | Where-Object { $_ -notmatch $GuidPattern })
                    if ($P.Licenses.Count -eq 0 -or $Invalid.Count -gt 0) { throw 'Licenses must be a list of licence SKU ids.' }
                    Set-CIPPUserLicense -UserId $UserObjectId -UserPrincipalName $Upn -TenantFilter $TenantFilter -AddLicenses @($P.Licenses) -Headers $Headers -APIName $APIName
                }
            }
            @{
                Key   = 'ResetPassword'
                Title = 'Reset password'
                Run   = { Set-CIPPResetPassword -UserID $Upn -DisplayName $User.displayName -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers }
            }
            @{
                Key   = 'IssueTAP'
                Title = 'Issue a Temporary Access Pass'
                Run   = { New-CIPPTAP -UserID $Upn -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers }
            }
            @{
                Key   = 'SetManager'
                Title = 'Set manager'
                Run   = {
                    if ([string]$P.ManagerId -notmatch $UserPattern) { throw 'ManagerId must be the object id or user principal name of the manager.' }
                    (Set-CIPPManager -Users $Upn -Manager $P.ManagerId -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers).Result
                }
            }
            @{
                Key   = 'AddGroups'
                Title = 'Add to groups'
                Run   = {
                    if ($P.Items.Count -eq 0) { throw 'No groups were given.' }
                    # A group that grants admin roles to its members may only be added to by a caller who can manage privileged users.
                    $RoleAssignable = @(if ($PrivilegedRestricted) { Get-CIPPRoleAssignableGroupId -GroupId @($P.Items.id | Where-Object { $_ -match $GuidPattern }) -TenantFilter $TenantFilter })
                    foreach ($Group in $P.Items) {
                        $GroupLabel = if ($Group.displayName) { $Group.displayName } else { $Group.id }
                        try {
                            if ([string]$Group.id -notmatch $GuidPattern) { throw 'the group id is not valid.' }
                            if ($RoleAssignable -contains [string]$Group.id) { throw 'it grants admin roles to its members, which needs the Identity.PrivilegedUser.ReadWrite permission.' }
                            # The live group wins; the type saved with the request can be missing or stale.
                            $Lookup = Get-CIPPGroupType -GroupId $Group.id -TenantFilter $TenantFilter
                            $ResolvedType = if ($Lookup.IsExchangeBacked -or $null -ne $Lookup.GroupObject.mailEnabled -or $null -ne $Lookup.GroupObject.securityEnabled) { $Lookup.GroupType }
                            $IsExchangeGroup = Test-CIPPGroupIsExchangeBacked -AddedFields @{ groupType = $Group.groupType } -ResolvedType $ResolvedType
                            try {
                                Add-CIPPGroupMember -Headers $Headers -GroupType ($ResolvedType ?? $Group.groupType) -GroupId $Group.id -Member @($Upn) -TenantFilter $TenantFilter -APIName $APIName
                            } catch {
                                # A user licensed moments ago is not an Exchange recipient yet, so the add is retried once,
                                # 15 minutes later; a slower mailbox fails visibly in the scheduler.
                                if (-not $IsExchangeGroup -or "$_" -notmatch "Ex94914C|ManagementObjectNotFoundException|couldn't be found|couldn't find|not found|does not exist") { throw }
                                $TaskBody = [PSCustomObject]@{
                                    TenantFilter  = $TenantFilter
                                    Name          = "Add Group Member: $Upn -> $GroupLabel"
                                    Command       = @{ value = 'Add-CIPPGroupMember' }
                                    Parameters    = [PSCustomObject]@{
                                        GroupType = $ResolvedType ?? 'Distribution List'
                                        GroupId   = $Group.id
                                        Member    = @($Upn)
                                        APIName   = 'Add Group Member (Onboarding)'
                                    }
                                    ScheduledTime = [int64](([datetime]::UtcNow).AddMinutes(15) - (Get-Date '1/1/1970')).TotalSeconds
                                    PostExecution = @{ Webhook = $false; Email = $false; PSA = $false }
                                }
                                $ScheduleResult = Add-CIPPScheduledTask -Task $TaskBody -hidden $false -Headers $Headers -DisallowDuplicateName $true
                                if ($ScheduleResult -like 'Successfully added task:*') {
                                    "Scheduled adding $Upn to $GroupLabel in 15 minutes, once Exchange has provisioned the mailbox."
                                } else {
                                    "Failed to schedule adding to group $($GroupLabel): $ScheduleResult"
                                }
                            }
                        } catch {
                            "Failed to add to group $($GroupLabel): $($_.Exception.Message)"
                        }
                    }
                }
            }
            @{
                Key   = 'CopyGroupsFrom'
                Title = 'Copy groups from another user'
                Run   = {
                    if ([string]$P.UserId -notmatch $UserPattern) { throw 'UserId must be the object id or user principal name of the user to copy groups from.' }
                    $Copy = Set-CIPPCopyGroupMembers -Headers $Headers -CopyFromId $P.UserId -UserId $Upn -TenantFilter $TenantFilter -APIName $APIName -SkipRoleAssignable:$PrivilegedRestricted
                    $Copy.Success
                    $Copy.Skipped
                    $Copy.Error | Where-Object { $_ } | ForEach-Object { "Error: $_" }
                }
            }
            @{
                Key   = 'RemoveOneDriveSiteAdmins'
                Title = 'Remove other OneDrive site admins'
                Run   = {
                    # The owner stays an admin of their own OneDrive whatever the request says.
                    $Admins = @($P.Items | ForEach-Object { [string]$_.User } | Where-Object { $_ -and $_ -ne $Upn })
                    if ($Admins.Count -eq 0) { throw 'No site admins to remove were given.' }
                    Set-CIPPSharePointPerms -UserId $Upn -OnedriveAccessUser $Admins -TenantFilter $TenantFilter -RemovePermission $true -APIName $APIName -Headers $Headers
                }
            }
            @{
                Key   = 'ConvertToUserMailbox'
                Title = 'Convert to a user mailbox'
                Run   = { Set-CIPPMailboxType -UserID $UserObjectId -Username $Upn -TenantFilter $TenantFilter -MailboxType 'Regular' -APIName $APIName -Headers $Headers }
            }
            @{
                Key   = 'UnhideFromGAL'
                Title = 'Show in the Global Address List'
                Run   = { Set-CIPPHideFromGAL -UserId $Upn -TenantFilter $TenantFilter -HideFromGAL $false -APIName $APIName -Headers $Headers }
            }
            @{
                Key   = 'RemoveForwarding'
                Title = 'Remove email forwarding'
                Run   = { Set-CIPPForwarding -UserID $UserObjectId -Username $Upn -TenantFilter $TenantFilter -Disable $true -APIName $APIName -Headers $Headers }
            }
            @{
                Key   = 'DisableOutOfOffice'
                Title = 'Turn off out of office'
                Run   = { Set-CIPPOutOfOffice -UserID $Upn -TenantFilter $TenantFilter -State 'Disabled' -APIName $APIName -Headers $Headers }
            }
            @{
                Key   = 'RemoveMailboxPermissions'
                Title = 'Remove mailbox delegates'
                Run   = {
                    if ($P.Items.Count -eq 0) { throw 'No mailbox delegates to remove were given.' }
                    foreach ($Item in $P.Items) {
                        $Rights = @($Item.AccessRights | Where-Object { $_ })
                        if (-not $Item.User -or $Rights.Count -eq 0) { 'Failed to remove a mailbox delegate: User and AccessRights are required.'; continue }
                        foreach ($Right in $Rights) {
                            if ($Right -notin 'FullAccess', 'SendAs', 'SendOnBehalf') { "Failed to remove $Right for $($Item.User): only FullAccess, SendAs and SendOnBehalf can be removed here."; continue }
                            # Reports its own failures as a returned 'Failed ...' line.
                            Set-CIPPMailboxPermission -UserId $Upn -AccessUser ([string]$Item.User) -PermissionLevel $Right -Action 'Remove' -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                        }
                    }
                }
            }
            @{
                Key   = 'RemoveCalendarPermissions'
                Title = 'Remove calendar delegates'
                Run   = {
                    if ($P.Items.Count -eq 0) { throw 'No calendar delegates to remove were given.' }
                    foreach ($Item in $P.Items) {
                        if (-not $Item.User -or -not $Item.FolderName) { 'Failed to remove a calendar delegate: User and FolderName are required.'; continue }
                        try {
                            Set-CIPPCalendarPermission -RemoveAccess ([string]$Item.User) -LoggingName ([string]$Item.Name) -UserID $Upn -FolderName ([string]$Item.FolderName) -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                        } catch {
                            "$($_.Exception.Message)"
                        }
                    }
                }
            }
            @{
                Key   = 'ProvisionOneDrive'
                Title = 'Pre-provision OneDrive'
                Run   = { Request-CIPPSPOPersonalSite -TenantFilter $TenantFilter -UserEmails @($Upn) -Headers $Headers -APIName $APIName }
            }
            @{
                Key   = 'SetMailboxLocale'
                Title = 'Set mailbox language and time zone'
                Run   = {
                    if ([string]::IsNullOrWhiteSpace($P.Locale)) { throw 'Locale is required, for example en-GB.' }
                    $LocaleParams = @{ Locale = $P.Locale; Username = $Upn; TenantFilter = $TenantFilter; APIName = $APIName; Headers = $Headers }
                    if ($P.TimeZone) { $LocaleParams.TimeZone = $P.TimeZone }
                    Set-CIPPMailboxLocale @LocaleParams
                }
            }
            @{
                Key   = 'EnableArchive'
                Title = 'Enable online archive'
                Run   = { Set-CIPPMailboxArchive -UserID $Upn -Username $Upn -TenantFilter $TenantFilter -ArchiveEnabled $true -APIName $APIName -Headers $Headers }
            }
            @{
                Key   = 'GrantMailboxAccess'
                Title = 'Give others access to the mailbox'
                Run   = {
                    if ($P.Items.Count -eq 0) { throw 'No people to give mailbox access to were given.' }
                    foreach ($Item in $P.Items) {
                        $Rights = @($Item.AccessRights | Where-Object { $_ })
                        if (-not $Item.User -or $Rights.Count -eq 0) { 'Failed to give mailbox access: User and AccessRights are required.'; continue }
                        foreach ($Right in $Rights) {
                            if ($Right -notin 'FullAccess', 'SendAs', 'SendOnBehalf') { "Failed to give $($Item.User) $Right`: only FullAccess, SendAs and SendOnBehalf can be given here."; continue }
                            # Reports its own failures as a returned 'Failed ...' line.
                            Set-CIPPMailboxPermission -UserId $Upn -AccessUser ([string]$Item.User) -PermissionLevel $Right -Action 'Add' -AutoMap ($Item.AutoMap -ne $false) -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                        }
                    }
                }
            }
            @{
                Key   = 'GrantCalendarAccess'
                Title = 'Give others access to the calendar'
                Run   = {
                    if ($P.Items.Count -eq 0) { throw 'No people to give calendar access to were given.' }
                    foreach ($Item in $P.Items) {
                        if (-not $Item.User -or $Item.Permissions -notin $CalendarRoles) { "Failed to give $($Item.User) calendar access: User and a calendar role ($($CalendarRoles -join ', ')) are required."; continue }
                        try {
                            Set-CIPPCalendarPermission -UserID $Upn -FolderName 'Calendar' -AutoResolveFolderName -UserToGetPermissions ([string]$Item.User) -Permissions ([string]$Item.Permissions) -CanViewPrivateItems ($Item.CanViewPrivateItems -eq $true) -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
                        } catch {
                            "$($_.Exception.Message)"
                        }
                    }
                }
            }
            @{
                Key   = 'AddOneDriveShortcuts'
                Title = 'Add SharePoint shortcuts to OneDrive'
                Run   = {
                    if ($P.Items.Count -eq 0) { throw 'No SharePoint libraries were given.' }
                    foreach ($Item in $P.Items) {
                        if ([string]$Item.URL -notmatch $SharePointUrlPattern) { "Failed to add a OneDrive shortcut: '$($Item.URL)' is not a SharePoint address."; continue }
                        try {
                            $ShortcutParams = @{ Username = $Upn; UserId = $UserObjectId; URL = [string]$Item.URL; TenantFilter = $TenantFilter; APIName = $APIName; Headers = $Headers }
                            if ($Item.ShortcutName) { $ShortcutParams.ShortcutName = [string]$Item.ShortcutName }
                            New-CIPPOneDriveShortCut @ShortcutParams
                        } catch {
                            "$($_.Exception.Message)"
                        }
                    }
                }
            }
        )

        $UnknownKeys = @($Requested.PSBase.Keys | Where-Object { $_ -notin $StepOrder.Key } | Sort-Object)
        if ($UnknownKeys.Count -gt 0) { throw "Unknown onboarding fix: $($UnknownKeys -join ', ')" }
        $Steps = @($StepOrder | Where-Object { $Requested.ContainsKey($_.Key) })
        if ($Steps.Count -eq 0) { throw "No onboarding fixes were selected for $Username." }
        if ($Username -notmatch $UserPattern) { throw 'Username must be an object id or user principal name.' }

        $RunIndexes = @(0..($Steps.Count - 1))
        if ($StepIndexes.Count -gt 0) {
            # Step re-run: the full list above keeps the indices stable; only the requested steps run.
            $RunIndexes = @($StepIndexes | Where-Object { $_ -ge 0 -and $_ -lt $Steps.Count })
            if ($RunIndexes.Count -eq 0) { throw "None of the requested steps ($($StepIndexes -join ', ')) exist for $Username" }
        }

        if ($DeploymentId) {
            if ($StepIndexes.Count -gt 0) {
                foreach ($Index in $RunIndexes) {
                    Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $Username -StepIndex $Index -StepStatus 'pending' -Message 'Waiting to start'
                }
            } else {
                try {
                    $null = New-CIPPAsyncDeployment -JobId $DeploymentId -Names @($Username) -StepTitles @($Steps.Title) -Source 'Onboarding' -TaskId $TaskInfo.RowKey -TenantFilter $TenantFilter
                } catch {
                    # Progress is a nice-to-have: a storage hiccup here must not fail the onboarding itself.
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Could not write the progress row for $Username : $($_.Exception.Message)" -sev Warning
                }
            }
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Username -Status 'running'
        }

        $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)?`$select=id,displayName,userPrincipalName" -tenantid $TenantFilter
        $UserObjectId = $User.id
        $Upn = $User.userPrincipalName
        if (-not $UserObjectId -or -not $Upn) { throw "Could not find the user $Username in $TenantFilter." }

        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Index in $RunIndexes) {
            $Step = $Steps[$Index]
            $P = $Requested[$Step.Key]
            $Progress = if ($DeploymentId) { @{ JobId = $DeploymentId; Name = $Username; StepIndex = $Index } }
            if ($Progress) { Set-CIPPAsyncDeploymentStep @Progress -StepStatus 'running' -Message 'In progress' }
            try {
                $StepResults = @(& $Step.Run | Where-Object { $null -ne $_ -and "$_" -ne '' })
            } catch {
                # Most helpers throw a full 'Failed ...' sentence; anything else gets the step named.
                $Message = [string]$_.Exception.Message
                $StepResults = @(if ($Message -match '^\s*(Error|Failed)\b') { $Message } else { "Failed to run '$($Step.Title)': $Message" })
            }
            foreach ($StepResult in $StepResults) { $Results.Add($StepResult) }
            if ($Progress) {
                # Helpers report per-item problems as returned 'Error: ...' or 'Failed ...' lines.
                $Lines = @($StepResults | ForEach-Object { [string]($_.resultText ?? $_) })
                $StepStatus = if (@($Lines | Where-Object { $_ -match '^\s*(Error|Failed)\b' }).Count -gt 0) { 'failed' } else { 'succeeded' }
                Set-CIPPAsyncDeploymentStep @Progress -StepStatus $StepStatus -Message ($Lines -join "`n")
            }
        }

        if ($DeploymentId) {
            # Close the row on every step it lists, so a clean step re-run does not hide an earlier failure.
            $Row = Get-CIPPAsyncDeployment -JobId $DeploymentId | Where-Object { $_.Name -eq $Username }
            $FinalStatus = if (@($Row.Steps | Where-Object { $_.Status -eq 'failed' }).Count -gt 0) { 'failed' } else { 'succeeded' }
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Username -Status $FinalStatus
        }
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Onboarding ran $($RunIndexes.Count) step(s) for $Username" -sev Info -headers $Headers
        return @($Results)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to run the onboarding job for $Username : $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage -headers $Headers
        if ($DeploymentId) {
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Username -Status 'failed' -Logs $ErrorMessage.NormalizedError
        }
        throw $ErrorMessage.NormalizedError
    }
}
