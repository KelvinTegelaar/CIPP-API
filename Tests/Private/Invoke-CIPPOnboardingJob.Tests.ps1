# Pester tests for Invoke-CIPPOnboardingJob: the fixes picked in the onboarding wizard become steps that
# run in a fixed order, one failure never stops the rest, and a step re-run touches only its own step.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:JobPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOnboardingJob.ps1'
    $script:EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecOnboardUser.ps1'

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message)" } }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TaskId, $TenantFilter) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Get-CIPPAsyncDeployment { param($JobId) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, $DisallowDuplicateName) }

    function Set-CIPPSignInState { param($UserID, [bool]$AccountEnabled, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPUserLicense { param($UserId, $UserPrincipalName, $AddLicenses, $TenantFilter, $Headers, $APIName) }
    function Set-CIPPResetPassword { param($UserID, $DisplayName, $TenantFilter, $APIName, $Headers) }
    function New-CIPPTAP { param($UserID, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPManager { param($Users, $Manager, $TenantFilter, $APIName, $Headers) }
    function Get-CIPPGroupType { param($GroupId, $TenantFilter) }
    function Test-CIPPGroupIsExchangeBacked { param($AddedFields, $ResolvedType) }
    function Add-CIPPGroupMember { param($Headers, $GroupType, $GroupId, $Member, $TenantFilter, $APIName) }
    function Set-CIPPCopyGroupMembers { param($Headers, $UserId, $CopyFromId, $TenantFilter, $APIName, [switch]$SkipRoleAssignable) }
    function Get-CIPPRoleAssignableGroupId { param([string[]]$GroupId, $TenantFilter) }
    function Set-CIPPSharePointPerms { param($UserId, $OnedriveAccessUser, $TenantFilter, $APIName, $RemovePermission, $Headers) }
    function Set-CIPPMailboxType { param($Headers, $UserID, $Username, $APIName, $TenantFilter, $MailboxType) }
    function Set-CIPPHideFromGAL { param($UserId, $TenantFilter, $APIName, [bool]$HideFromGAL, $Headers) }
    function Set-CIPPForwarding { param($UserID, $TenantFilter, $Username, $Headers, $APIName, [bool]$Disable) }
    function Set-CIPPOutOfOffice { param($UserID, $TenantFilter, $State, $APIName, $Headers) }
    function Set-CIPPMailboxPermission { param($UserId, $AccessUser, $PermissionLevel, $Action, [bool]$AutoMap = $true, $TenantFilter, $APIName, $Headers) }
    function Set-CIPPCalendarPermission { param($APIName, $Headers, $RemoveAccess, $LoggingName, $TenantFilter, $UserID, $FolderName, $UserToGetPermissions, $Permissions, [bool]$CanViewPrivateItems, [switch]$AutoResolveFolderName) }
    function Request-CIPPSPOPersonalSite { param($TenantFilter, [string[]]$UserEmails, $Headers, $APIName) }
    function Set-CIPPMailboxLocale { param($Headers, $Locale, $Username, $APIName, $TenantFilter, $TimeZone) }
    function Set-CIPPMailboxArchive { param($Headers, $UserID, $Username, $APIName, $TenantFilter, [bool]$ArchiveEnabled) }
    function New-CIPPOneDriveShortCut { param($Username, $UserId, $URL, $TenantFilter, $APIName, $Headers, $ShortcutName) }

    . $script:JobPath

    $script:Group1 = '11111111-1111-1111-1111-111111111111'
    $script:Sku1 = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:Sku2 = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

    function Invoke-Job {
        param([object[]]$Fixes, [int[]]$StepIndexes = @(), [string]$DeploymentId = 'job-1')
        Invoke-CIPPOnboardingJob -TenantFilter 'contoso.com' -Username 'maria@contoso.com' -Options @{ Fixes = $Fixes } -DeploymentId $DeploymentId -StepIndexes $StepIndexes -TaskInfo ([pscustomobject]@{ RowKey = 'task-1' })
    }
}

Describe 'Invoke-CIPPOnboardingJob' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:StepTitles = $null
        $script:StepUpdates = [System.Collections.Generic.List[object]]::new()
        Mock Write-LogMessage { }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'user-id-1'; displayName = 'Maria Jensen'; userPrincipalName = 'maria@contoso.com' } }
        Mock New-CIPPAsyncDeployment { $script:StepTitles = @($StepTitles); $JobId }
        Mock Set-CIPPAsyncDeploymentStatus { }
        Mock Set-CIPPAsyncDeploymentStep { $script:StepUpdates.Add([pscustomobject]@{ Index = $StepIndex; Status = $StepStatus; Message = $Message }) }
        Mock Get-CIPPAsyncDeployment { }
        Mock Add-CIPPScheduledTask { 'Successfully added task: x' }

        Mock Set-CIPPSignInState { $script:Calls.Add('EnableSignIn'); 'Successfully set account enabled state' }
        Mock Set-CIPPUserLicense { $script:Calls.Add('AssignLicenses'); 'Successfully set licenses' }
        Mock Set-CIPPResetPassword { $script:Calls.Add('ResetPassword'); [pscustomobject]@{ resultText = 'Successfully reset the password. The new password is Pw1'; copyField = 'Pw1'; state = 'success' } }
        Mock New-CIPPTAP { $script:Calls.Add('IssueTAP'); @{ resultText = 'The TAP for maria@contoso.com is 123'; state = 'success' } }
        Mock Set-CIPPManager { $script:Calls.Add('SetManager'); [pscustomobject]@{ Result = "Set manager to $Manager" } }
        Mock Get-CIPPGroupType { [pscustomobject]@{ GroupType = 'Security'; IsExchangeBacked = $false; GroupObject = [pscustomobject]@{ mailEnabled = $false; securityEnabled = $true } } }
        Mock Test-CIPPGroupIsExchangeBacked { $ResolvedType -in 'Distribution List', 'Mail-Enabled Security' }
        Mock Add-CIPPGroupMember { $script:Calls.Add('AddGroups'); "Successfully added to group $GroupId." }
        Mock Set-CIPPCopyGroupMembers { $script:Calls.Add('CopyGroupsFrom'); [pscustomobject]@{ Success = @('Added user to group: A'); Error = @(); Skipped = @() } }
        Mock Set-CIPPSharePointPerms { $script:Calls.Add('RemoveOneDriveSiteAdmins'); [pscustomobject]@{ resultText = 'Successfully removed'; state = 'success' } }
        Mock Set-CIPPMailboxType { $script:Calls.Add('ConvertToUserMailbox'); 'Successfully converted' }
        Mock Set-CIPPHideFromGAL { $script:Calls.Add('UnhideFromGAL'); 'Successfully unhidden' }
        Mock Set-CIPPForwarding { $script:Calls.Add('RemoveForwarding'); 'Successfully disabled forwarding' }
        Mock Set-CIPPOutOfOffice { $script:Calls.Add('DisableOutOfOffice'); 'Set Out-of-office to Disabled.' }
        Mock Set-CIPPMailboxPermission { $script:Calls.Add($(if ($Action -eq 'Add') { 'GrantMailboxAccess' } else { 'RemoveMailboxPermissions' })); "$Action $AccessUser $PermissionLevel on $UserId" }
        Mock Set-CIPPCalendarPermission { $script:Calls.Add($(if ($RemoveAccess) { 'RemoveCalendarPermissions' } else { 'GrantCalendarAccess' })); "Successfully set calendar access for $RemoveAccess$UserToGetPermissions" }
        Mock Request-CIPPSPOPersonalSite { $script:Calls.Add('ProvisionOneDrive'); 'Successfully requested personal site' }
        Mock Set-CIPPMailboxLocale { $script:Calls.Add('SetMailboxLocale'); "Set locale to $Locale" }
        Mock Set-CIPPMailboxArchive { $script:Calls.Add('EnableArchive'); 'Successfully set archive' }
        Mock New-CIPPOneDriveShortCut { $script:Calls.Add('AddOneDriveShortcuts'); 'Successfully created OneDrive Shortcut' }
    }

    It 'runs the steps in the fixed order whatever order they were requested in' {
        $null = Invoke-Job -Fixes @(
            @{ Key = 'DisableOutOfOffice' }
            @{ Key = 'IssueTAP' }
            @{ Key = 'AssignLicenses'; Params = @{ Licenses = @($script:Sku1) } }
            @{ Key = 'EnableSignIn'; Params = @{} }
        )
        $script:Calls | Should -Be @('EnableSignIn', 'AssignLicenses', 'IssueTAP', 'DisableOutOfOffice')
        $script:StepTitles | Should -Be @('Enable sign-in', 'Assign licences', 'Issue a Temporary Access Pass', 'Turn off out of office')
        Should -Invoke New-CIPPAsyncDeployment -Times 1 -Exactly -ParameterFilter { $JobId -eq 'job-1' -and $Source -eq 'Onboarding' -and $TaskId -eq 'task-1' -and $TenantFilter -eq 'contoso.com' }
    }

    It 'has one step for every key the endpoint allows, in the same order' {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:EndpointPath, [ref]$null, [ref]$null)
        $Assignment = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Left.Extent.Text -eq '$AllowedKeys' }, $true)
        $AllowedKeys = @($Assignment.Right.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value)
        $AllowedKeys.Count | Should -Be 20
        # The post-licence steps come last, after everything that undoes an offboarding.
        $AllowedKeys[-6..-1] | Should -Be @('ProvisionOneDrive', 'SetMailboxLocale', 'EnableArchive', 'GrantMailboxAccess', 'GrantCalendarAccess', 'AddOneDriveShortcuts')

        $Items = @(@{ User = 'tom@contoso.com'; AccessRights = @('FullAccess'); FolderName = 'Calendar'; id = $script:Group1; Permissions = 'Reviewer'; URL = 'https://contoso.sharepoint.com/sites/Sales/Shared Documents' })
        $Fixes = foreach ($Key in $AllowedKeys) { @{ Key = $Key; Params = @{ Items = $Items; Licenses = @($script:Sku1); ManagerId = 'boss@contoso.com'; UserId = 'peer@contoso.com'; Locale = 'en-GB' } } }
        [array]::Reverse($Fixes)
        $null = Invoke-Job -Fixes $Fixes
        $script:Calls | Should -Be $AllowedKeys
    }

    It 'merges repeated keys into one step' {
        $Results = Invoke-Job -Fixes @(
            @{ Key = 'RemoveMailboxPermissions'; Params = @{ Items = @(@{ User = 'tom@contoso.com'; AccessRights = @('FullAccess', 'SendAs') }) } }
            @{ Key = 'AssignLicenses'; Params = @{ Licenses = @($script:Sku1) } }
            @{ Key = 'RemoveMailboxPermissions'; Params = @{ Items = @(@{ User = 'ann@contoso.com'; AccessRights = @('SendOnBehalf') }) } }
            @{ Key = 'AssignLicenses'; Params = @{ Licenses = @($script:Sku2, $script:Sku1) } }
        )
        $script:StepTitles | Should -Be @('Assign licences', 'Remove mailbox delegates')
        Should -Invoke Set-CIPPUserLicense -Times 1 -Exactly -ParameterFilter { (@($AddLicenses) -join ',') -eq "$($script:Sku1),$($script:Sku2)" -and $UserId -eq 'user-id-1' }
        Should -Invoke Set-CIPPMailboxPermission -Times 3 -Exactly -ParameterFilter { $UserId -eq 'maria@contoso.com' -and $Action -eq 'Remove' }
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $AccessUser -eq 'ann@contoso.com' -and $PermissionLevel -eq 'SendOnBehalf' }
        @($Results).Count | Should -Be 4
    }

    It 'reports a throwing step as failed and still runs the later steps' {
        Mock Set-CIPPUserLicense { throw 'no licences left' }
        Mock Get-CIPPAsyncDeployment { [pscustomobject]@{ Name = 'maria@contoso.com'; Steps = @([pscustomobject]@{ Status = 'succeeded' }, [pscustomobject]@{ Status = 'failed' }, [pscustomobject]@{ Status = 'succeeded' }) } }
        $Results = Invoke-Job -Fixes @(@{ Key = 'EnableSignIn' }, @{ Key = 'AssignLicenses'; Params = @{ Licenses = @($script:Sku1) } }, @{ Key = 'UnhideFromGAL' })

        $script:Calls | Should -Be @('EnableSignIn', 'UnhideFromGAL')
        @($Results)[1] | Should -Be "Failed to run 'Assign licences': no licences left"
        ($script:StepUpdates | Where-Object { $_.Index -eq 1 -and $_.Status -eq 'failed' }).Message | Should -BeLike '*no licences left*'
        @($script:StepUpdates | Where-Object { $_.Index -eq 2 -and $_.Status -eq 'succeeded' }).Count | Should -Be 1
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -Exactly -ParameterFilter { $Status -eq 'failed' }
    }

    It 'fails a step whose helper returns an error line instead of throwing' {
        Mock Set-CIPPMailboxPermission { "Failed to Remove $PermissionLevel for $AccessUser" }
        $null = Invoke-Job -Fixes @(@{ Key = 'RemoveMailboxPermissions'; Params = @{ Items = @(@{ User = 'tom@contoso.com'; AccessRights = @('FullAccess') }) } })
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 1
    }

    It 'runs only the requested steps on a step re-run and keeps the row' {
        $null = Invoke-Job -StepIndexes 1 -Fixes @(@{ Key = 'UnhideFromGAL' }, @{ Key = 'EnableSignIn' }, @{ Key = 'ResetPassword' })

        $script:Calls | Should -Be @('ResetPassword')
        Should -Invoke New-CIPPAsyncDeployment -Times 0 -Exactly
        @($script:StepUpdates.Index | Sort-Object -Unique) | Should -Be @(1)
        $script:StepUpdates[0].Status | Should -Be 'pending'
        $script:StepUpdates[-1].Message | Should -BeLike '*The new password is Pw1*'
    }

    It 'refuses a step re-run for a step that does not exist' {
        { Invoke-Job -StepIndexes 5 -Fixes @(@{ Key = 'EnableSignIn' }) } | Should -Throw '*None of the requested steps*'
        $script:Calls.Count | Should -Be 0
    }

    It 'refuses an unknown key by name and runs nothing' {
        { Invoke-Job -Fixes @(@{ Key = 'EnableSignIn' }, @{ Key = 'AssignAdminRole' }) } | Should -Throw '*AssignAdminRole*'
        $script:Calls.Count | Should -Be 0
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -Exactly -ParameterFilter { $Status -eq 'failed' }
    }

    It 'refuses an empty list of fixes' {
        { Invoke-Job -Fixes @() } | Should -Throw '*No onboarding fixes were selected*'
    }

    It 'reads fixes the scheduler stored as JSON' {
        $null = Invoke-CIPPOnboardingJob -TenantFilter 'contoso.com' -Username 'maria@contoso.com' -Options '{"Fixes":[{"Key":"RemoveForwarding","Params":{}}]}'
        $script:Calls | Should -Be @('RemoveForwarding')
        Should -Invoke Set-CIPPAsyncDeploymentStep -Times 0 -Exactly
    }

    It 'runs the post-licence steps against the onboarded user with the given settings' {
        $null = Invoke-Job -Fixes @(
            @{ Key = 'AddOneDriveShortcuts'; Params = @{ Items = @(@{ URL = 'https://contoso.sharepoint.com/sites/Sales/Shared Documents'; ShortcutName = 'Sales' }) } }
            @{ Key = 'GrantCalendarAccess'; Params = @{ Items = @(@{ User = 'boss@contoso.com'; Permissions = 'Editor'; CanViewPrivateItems = $true }) } }
            @{ Key = 'GrantMailboxAccess'; Params = @{ Items = @(@{ User = 'boss@contoso.com'; AccessRights = @('FullAccess', 'SendAs'); AutoMap = $false }) } }
            @{ Key = 'EnableArchive' }
            @{ Key = 'SetMailboxLocale'; Params = @{ Locale = 'en-GB'; TimeZone = 'GMT Standard Time' } }
            @{ Key = 'ProvisionOneDrive' }
            @{ Key = 'EnableSignIn' }
        )
        $script:Calls | Should -Be @('EnableSignIn', 'ProvisionOneDrive', 'SetMailboxLocale', 'EnableArchive', 'GrantMailboxAccess', 'GrantMailboxAccess', 'GrantCalendarAccess', 'AddOneDriveShortcuts')
        $script:StepTitles[1..6] | Should -Be @('Pre-provision OneDrive', 'Set mailbox language and time zone', 'Enable online archive', 'Give others access to the mailbox', 'Give others access to the calendar', 'Add SharePoint shortcuts to OneDrive')

        Should -Invoke Request-CIPPSPOPersonalSite -Times 1 -Exactly -ParameterFilter { $UserEmails.Count -eq 1 -and $UserEmails[0] -eq 'maria@contoso.com' -and $TenantFilter -eq 'contoso.com' }
        Should -Invoke Set-CIPPMailboxLocale -Times 1 -Exactly -ParameterFilter { $Username -eq 'maria@contoso.com' -and $Locale -eq 'en-GB' -and $TimeZone -eq 'GMT Standard Time' }
        Should -Invoke Set-CIPPMailboxArchive -Times 1 -Exactly -ParameterFilter { $UserID -eq 'maria@contoso.com' -and $ArchiveEnabled -eq $true }
        Should -Invoke Set-CIPPMailboxPermission -Times 2 -Exactly -ParameterFilter { $Action -eq 'Add' -and $UserId -eq 'maria@contoso.com' -and $AccessUser -eq 'boss@contoso.com' -and $AutoMap -eq $false }
        Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly -ParameterFilter { $UserID -eq 'maria@contoso.com' -and $UserToGetPermissions -eq 'boss@contoso.com' -and $Permissions -eq 'Editor' -and $CanViewPrivateItems -and $AutoResolveFolderName -and -not $RemoveAccess }
        Should -Invoke New-CIPPOneDriveShortCut -Times 1 -Exactly -ParameterFilter { $Username -eq 'maria@contoso.com' -and $UserId -eq 'user-id-1' -and $URL -eq 'https://contoso.sharepoint.com/sites/Sales/Shared Documents' -and $ShortcutName -eq 'Sales' }
    }

    It 'leaves the time zone alone when none is given and automaps by default' {
        $null = Invoke-Job -Fixes @(
            @{ Key = 'SetMailboxLocale'; Params = @{ Locale = 'nl-NL' } }
            @{ Key = 'GrantMailboxAccess'; Params = @{ Items = @(@{ User = 'boss@contoso.com'; AccessRights = @('FullAccess') }) } }
        )
        Should -Invoke Set-CIPPMailboxLocale -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('TimeZone') }
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $AutoMap -eq $true }
    }

    It 'fails the locale step when no locale is given' {
        $null = Invoke-Job -Fixes @(@{ Key = 'SetMailboxLocale'; Params = @{ TimeZone = 'GMT Standard Time' } })
        Should -Invoke Set-CIPPMailboxLocale -Times 0 -Exactly
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 1
    }

    It 'only gives the three delegate rights, reporting anything else as failed' {
        $null = Invoke-Job -Fixes @(@{ Key = 'GrantMailboxAccess'; Params = @{ Items = @(@{ User = 'tom@contoso.com'; AccessRights = @('ChangeOwner', 'SendOnBehalf') }) } })
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $PermissionLevel -eq 'SendOnBehalf' -and $Action -eq 'Add' -and $UserId -eq 'maria@contoso.com' }
        ($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Message | Should -BeLike '*Failed to give tom@contoso.com ChangeOwner*'
    }

    It 'refuses a calendar role outside the list and still sets the next one' {
        $null = Invoke-Job -Fixes @(@{ Key = 'GrantCalendarAccess'; Params = @{ Items = @(@{ User = 'tom@contoso.com'; Permissions = 'Owner; Remove-Mailbox' }, @{ User = 'ann@contoso.com'; Permissions = 'Reviewer' }) } })
        Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly
        Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly -ParameterFilter { $UserToGetPermissions -eq 'ann@contoso.com' -and $CanViewPrivateItems -eq $false }
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 1
    }

    It 'refuses a shortcut address that is not SharePoint over https: <Url>' -ForEach @(
        @{ Url = 'http://contoso.sharepoint.com/sites/Sales' }
        @{ Url = 'https://contoso.sharepoint.com.evil.example/sites/Sales' }
        @{ Url = 'https://evil.example/?x=https://contoso.sharepoint.com/' }
        @{ Url = '' }
    ) {
        $null = Invoke-Job -Fixes @(@{ Key = 'AddOneDriveShortcuts'; Params = @{ Items = @(@{ URL = $Url }, @{ URL = 'https://contoso.sharepoint.com/sites/HR' }) } })
        Should -Invoke New-CIPPOneDriveShortCut -Times 1 -Exactly -ParameterFilter { $URL -eq 'https://contoso.sharepoint.com/sites/HR' }
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 1
    }

    It 'pre-provisions the OneDrive ahead of a shortcut even when that was not asked for' {
        $null = Invoke-Job -Fixes @(@{ Key = 'AddOneDriveShortcuts'; Params = @{ Items = @(@{ URL = 'https://contoso.sharepoint.com/sites/hr' }) } })

        Should -Invoke Request-CIPPSPOPersonalSite -Times 1 -Exactly
        Should -Invoke New-CIPPOneDriveShortCut -Times 1 -Exactly
        @($script:Calls) | Should -Be @('ProvisionOneDrive', 'AddOneDriveShortcuts')
    }

    It 'reports a shortcut that fails and still adds the next one' {
        $script:Shortcuts = 0
        Mock New-CIPPOneDriveShortCut { $script:Shortcuts++; if ($script:Shortcuts -eq 1) { throw 'Failed to create OneDrive Shortcut: no OneDrive yet' }; 'Successfully created OneDrive Shortcut' }
        $Results = Invoke-Job -Fixes @(@{ Key = 'AddOneDriveShortcuts'; Params = @{ Items = @(@{ URL = 'https://contoso.sharepoint.com/sites/A' }, @{ URL = 'https://contoso.sharepoint.com/sites/B' }) } })
        $Results | Should -Contain 'Successfully created OneDrive Shortcut'
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 1
    }

    It 'reports a shortcut error the helper throws as Could not ... as a failed step' {
        Mock New-CIPPOneDriveShortCut { throw 'Could not add OneDrive shortcut to maria@contoso.com : Could not find a SharePoint site matching URL' }
        $Results = Invoke-Job -Fixes @(@{ Key = 'AddOneDriveShortcuts'; Params = @{ Items = @(@{ URL = 'https://contoso.sharepoint.com/sites/A' }) } })
        @($Results)[-1] | Should -BeLike 'Failed to add the OneDrive shortcut to https://contoso.sharepoint.com/sites/A:*'
        Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 1
    }

    It 'schedules a shortcut for later when the OneDrive is not ready yet' {
        Mock New-CIPPOneDriveShortCut { throw "Could not add OneDrive shortcut to maria@contoso.com : User's mysite not found." }
        $Results = Invoke-Job -Fixes @(@{ Key = 'AddOneDriveShortcuts'; Params = @{ Items = @(@{ URL = 'https://contoso.sharepoint.com/sites/Sales'; ShortcutName = 'Sales' }) } })

        Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $Task.Command.value -eq 'New-CIPPOneDriveShortCut' -and $Task.Parameters.Username -eq 'maria@contoso.com' -and $Task.Parameters.UserId -eq 'user-id-1' -and $Task.Parameters.URL -eq 'https://contoso.sharepoint.com/sites/Sales' -and $Task.Parameters.ShortcutName -eq 'Sales' -and $Task.ScheduledTime -gt 0 }
        @($Results)[-1] | Should -BeLike 'Scheduled adding the OneDrive shortcut to Sales in 30 minutes*'
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 0
    }

    It 'only removes the three delegate rights and only from the onboarded mailbox' {
        $null = Invoke-Job -Fixes @(@{ Key = 'RemoveMailboxPermissions'; Params = @{ Items = @(@{ User = 'tom@contoso.com'; AccessRights = @('ChangeOwner', 'SendAs') }) } })
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly
        Should -Invoke Set-CIPPMailboxPermission -Times 1 -Exactly -ParameterFilter { $PermissionLevel -eq 'SendAs' -and $UserId -eq 'maria@contoso.com' }
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 1
    }

    It 'never removes the owner from their own OneDrive' {
        $null = Invoke-Job -Fixes @(@{ Key = 'RemoveOneDriveSiteAdmins'; Params = @{ Items = @(@{ User = 'maria@contoso.com' }, @{ User = 'tom@contoso.com' }) } })
        Should -Invoke Set-CIPPSharePointPerms -Times 1 -Exactly -ParameterFilter { (@($OnedriveAccessUser) -join ',') -eq 'tom@contoso.com' -and $RemovePermission -eq $true -and $UserId -eq 'maria@contoso.com' }
    }

    It 'looks up <Upn> with the UPN encoded in the Graph path' -ForEach @(
        @{ Upn = "sean.o'brien@contoso.com"; Encoded = 'sean.o%27brien%40contoso.com' }
        @{ Upn = 'guest_fabrikam.com#EXT#@contoso.onmicrosoft.com'; Encoded = 'guest_fabrikam.com%23EXT%23%40contoso.onmicrosoft.com' }
    ) {
        $null = Invoke-CIPPOnboardingJob -TenantFilter 'contoso.com' -Username $Upn -Options @{ Fixes = @(@{ Key = 'EnableArchive' }) } -DeploymentId 'job-1' -TaskInfo ([pscustomobject]@{ RowKey = 'task-1' })
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -eq "https://graph.microsoft.com/beta/users/$Encoded`?`$select=id,displayName,userPrincipalName" }
        Should -Invoke Set-CIPPMailboxArchive -Times 1 -Exactly
    }

    It 'refuses a manager value carrying a replacement variable' {
        $null = Invoke-Job -Fixes @(@{ Key = 'SetManager'; Params = @{ ManagerId = '%manager%' } })
        Should -Invoke Set-CIPPManager -Times 0 -Exactly
        @($script:StepUpdates | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 1
    }

    It 'schedules an Exchange group add for later when the user is not a recipient yet' {
        Mock Get-CIPPGroupType { [pscustomobject]@{ GroupType = 'Distribution List'; IsExchangeBacked = $true; GroupObject = [pscustomobject]@{ mailEnabled = $true; securityEnabled = $false } } }
        Mock Add-CIPPGroupMember { throw "Failed to add maria@contoso.com to group Sales - Couldn't find object" }
        $Results = Invoke-Job -Fixes @(@{ Key = 'AddGroups'; Params = @{ Items = @(@{ id = $script:Group1; displayName = 'Sales'; groupType = 'distributionList' }) } })

        Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter { $Task.Command.value -eq 'Add-CIPPGroupMember' -and $Task.Parameters.GroupId -eq $script:Group1 -and $Task.Parameters.Member -eq 'maria@contoso.com' -and $Task.ScheduledTime -gt 0 }
        @($Results)[0] | Should -BeLike 'Scheduled adding maria@contoso.com to Sales in 15 minutes*'
        @($script:StepUpdates | Where-Object { $_.Status -eq 'succeeded' }).Count | Should -Be 1
    }

    Context 'Groups that grant admin roles' {
        BeforeEach {
            $script:Group2 = '22222222-2222-2222-2222-222222222222'
            $script:Group3 = '33333333-3333-3333-3333-333333333333'
            Mock Add-CIPPGroupMember { 'Successfully added' }
            Mock Get-CIPPRoleAssignableGroupId { $script:Group2, $script:Group3 }
            $script:GroupFixes = @(
                @{ Key = 'AddGroups'; Params = @{ Items = @(@{ id = $script:Group1; displayName = 'Plain' }, @{ id = $script:Group2; displayName = 'Admins' }, @{ id = $script:Group3; displayName = 'Unreadable' }) } }
                @{ Key = 'CopyGroupsFrom'; Params = @{ UserId = 'peer@contoso.com' } }
            )
        }
        AfterEach { $script:CippPrivilegedUserRestrictedStorage = $null }

        It 'are refused for a task queued without the privileged permission' {
            $script:CippPrivilegedUserRestrictedStorage = [pscustomobject]@{ Value = $true }
            $Results = Invoke-Job -Fixes $script:GroupFixes

            Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter { $GroupId -eq $script:Group1 }
            @($Results) -like 'Failed to add to group Admins*Identity.PrivilegedUser.ReadWrite*' | Should -HaveCount 1
            @($Results) -like 'Failed to add to group Unreadable*' | Should -HaveCount 1
            Should -Invoke Set-CIPPCopyGroupMembers -Times 1 -Exactly -ParameterFilter { $SkipRoleAssignable }
        }

        It 'are added for a caller who can manage privileged users, without the extra lookup' {
            $null = Invoke-Job -Fixes $script:GroupFixes

            Should -Invoke Add-CIPPGroupMember -Times 3 -Exactly
            Should -Invoke Get-CIPPRoleAssignableGroupId -Times 0 -Exactly
            Should -Invoke Set-CIPPCopyGroupMembers -Times 1 -Exactly -ParameterFilter { -not $SkipRoleAssignable }
        }
    }

    It 'reports a failed Graph group add without scheduling, and still adds the next group' {
        $script:Adds = 0
        Mock Add-CIPPGroupMember { $script:Adds++; if ($script:Adds -eq 1) { throw 'Failed to add: not found' }; 'Successfully added' }
        $Results = Invoke-Job -Fixes @(@{ Key = 'AddGroups'; Params = @{ Items = @(@{ id = $script:Group1; displayName = 'One' }, @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Two' }, @{ id = 'not-a-guid'; displayName = 'Three' }) } })
        Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        @($Results) | Should -HaveCount 3
        @($Results)[0] | Should -BeLike 'Failed to add to group One*'
        @($Results)[1] | Should -Be 'Successfully added'
        @($Results)[2] | Should -BeLike 'Failed to add to group Three*'
    }
}
