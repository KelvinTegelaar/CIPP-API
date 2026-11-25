function Get-CIPPUserOnboardingScan {
    <#
    .SYNOPSIS
        Scans an existing account for what an offboarding left behind.

    .DESCRIPTION
        The mirror image of Invoke-CIPPOffboardingJob: reads the account, mailbox, delegated access and
        entitlements of a returning user and returns one finding per thing a technician may want to
        undo, each with the fix the onboarding job can run. The offboarding snapshot, when there is
        one, is returned with live licence availability and whether each group can be restored.

        A check that fails adds an entry to Errors and the others still return. A soft-deleted user
        returns only the SoftDeleted finding.

    .OUTPUTS
        PSCustomObject with User, Snapshot, Findings and Errors.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # Object id or userPrincipalName
        [Parameter(Mandatory = $true)]
        [string]$UserId,

        $Headers
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Errors = [System.Collections.Generic.List[object]]::new()
    # Guest UPNs contain '#EXT#'; unencoded, the '#' truncates the Graph path.
    $EncodedUser = [System.Uri]::EscapeDataString($UserId)

    $CoreRequests = @(
        @{ id = 'user'; method = 'GET'; url = "users/$($EncodedUser)?`$select=id,userPrincipalName,displayName,accountEnabled,onPremisesSyncEnabled,onPremisesImmutableId,assignedLicenses" }
        @{ id = 'groups'; method = 'GET'; url = "users/$EncodedUser/memberOf/microsoft.graph.group?`$select=id&`$top=999" }
        @{ id = 'devices'; method = 'GET'; url = "users/$EncodedUser/ownedDevices?`$select=id" }
        @{ id = 'skus'; method = 'GET'; url = 'subscribedSkus?$select=skuId,skuPartNumber,prepaidUnits,consumedUnits' }
    )
    $CoreResponses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $CoreRequests)
    $Core = @{}
    foreach ($Response in $CoreResponses) {
        $Core[[string]$Response.id] = $Response
    }

    if ($Core['user'].status -eq 404) {
        # A deleted user's UPN is prefixed with its object id, so match on the tail as well.
        $Deleted = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/microsoft.graph.user?`$select=id,displayName,userPrincipalName,mail,deletedDateTime,onPremisesSyncEnabled&`$top=999" -tenantid $TenantFilter).Where({
                $_.id -eq $UserId -or $_.mail -eq $UserId -or ([string]$_.userPrincipalName).EndsWith($UserId, [System.StringComparison]::OrdinalIgnoreCase)
            }, 'First')
        if ($Deleted.Count -eq 0) {
            throw [System.Management.Automation.ItemNotFoundException]::new("User $UserId was not found in $TenantFilter, including deleted users.")
        }
        $DeletedUser = $Deleted[0]
        $Upn = [string]$DeletedUser.userPrincipalName -replace '^[0-9a-fA-F]{32}(?=.+@)', ''
        $Findings.Add([pscustomobject]@{
                Id       = 'SoftDeleted'
                Category = 'Account'
                Title    = 'User is deleted'
                Detail   = "$($DeletedUser.displayName) is in deleted users. Restore the account before anything else can be checked."
                Note     = $null
                Fix      = @{ Key = 'RestoreUser'; Label = 'Restore user'; Default = $true; Params = @{} }
            })
        return [pscustomobject]@{
            User     = [pscustomobject]@{
                id                    = $DeletedUser.id
                userPrincipalName     = $Upn
                displayName           = $DeletedUser.displayName
                accountEnabled        = $false
                deleted               = $true
                deletedDateTime       = $DeletedUser.deletedDateTime
                onPremisesSyncEnabled = $DeletedUser.onPremisesSyncEnabled -eq $true
            }
            Snapshot = $null
            Findings = $Findings.ToArray()
            Errors   = $Errors.ToArray()
        }
    }
    if ($Core['user'].status -ne 200) {
        throw "Could not read user $UserId`: $($Core['user'].body.error.message ?? "HTTP $($Core['user'].status)")"
    }

    $User = $Core['user'].body
    $Upn = [string]$User.userPrincipalName
    $IsSynced = $User.onPremisesSyncEnabled -eq $true
    $SignInBlocked = $User.accountEnabled -eq $false
    $Licensed = @($User.assignedLicenses | Where-Object { $_.skuId }).Count -gt 0

    #region Account
    if ($SignInBlocked) {
        $Findings.Add([pscustomobject]@{
                Id = 'SignInBlocked'; Category = 'Account'; Title = 'Sign-in is blocked'
                Detail = 'The account is disabled, so the user cannot sign in.'; Note = $null
                Fix = @{ Key = 'EnableSignIn'; Label = 'Enable sign-in'; Default = $true; Params = @{} }
            })
    }
    $PasswordDetail = if ($IsSynced) {
        'This account is synced from Active Directory, so reset the password on-premises unless password writeback is enabled.'
    } elseif ($SignInBlocked) {
        'Offboarding usually resets the password. Set a new one for the returning user.'
    } else {
        'Set a new password if the user no longer knows the current one.'
    }
    $Findings.Add([pscustomobject]@{
            Id = 'PasswordReset'; Category = 'Account'; Title = 'Reset the password'; Detail = $PasswordDetail; Note = $null
            Fix = @{ Key = 'ResetPassword'; Label = 'Reset password'; Default = ($SignInBlocked -and -not $IsSynced); Params = @{} }
        })
    $Findings.Add([pscustomobject]@{
            Id = 'TemporaryAccessPass'; Category = 'Account'; Title = 'Issue a Temporary Access Pass'
            Detail = 'A time-limited passcode lets the user sign in and register new sign-in methods.'; Note = $null
            Fix = @{ Key = 'IssueTAP'; Label = 'Issue Temporary Access Pass'; Default = $false; Params = @{} }
        })

    # Sign-in methods and the OneDrive site need the application's own permissions.
    $AppOnly = @{}
    try {
        $AppOnlyRequests = @(
            @{ id = 'methods'; method = 'GET'; url = "users/$($User.id)/authentication/methods" }
            @{ id = 'drive'; method = 'GET'; url = "users/$($User.id)/drive/root?`$select=sharepointIds" }
        )
        $AppOnlyResponses = @(New-GraphBulkRequest -tenantid $TenantFilter -asapp $true -Requests $AppOnlyRequests)
        foreach ($Response in $AppOnlyResponses) {
            $AppOnly[[string]$Response.id] = $Response
        }
        if ($AppOnly['methods'].status -ne 200) {
            $Errors.Add(@{ Check = 'MFA methods'; Message = [string]($AppOnly['methods'].body.error.message ?? "HTTP $($AppOnly['methods'].status)") })
        } elseif (@($AppOnly['methods'].body.value | Where-Object { $_.'@odata.type' -and $_.'@odata.type' -notin '#microsoft.graph.passwordAuthenticationMethod', '#microsoft.graph.emailAuthenticationMethod' }).Count -eq 0) {
            $Findings.Add([pscustomobject]@{
                    Id = 'NoMfaMethods'; Category = 'Account'; Title = 'No MFA methods registered'
                    Detail = 'The user has no multi-factor sign-in methods and will have to register again at first sign-in.'
                    Note = 'Report only'; Fix = $null
                })
        }
    } catch {
        $Errors.Add(@{ Check = 'MFA methods'; Message = (Get-CippException -Exception $_).NormalizedError })
    }
    #endregion Account

    #region Mailbox and delegated access
    try {
        $MailboxCmdlets = @(
            @{ CmdletInput = @{ CmdletName = 'Get-Mailbox'; Parameters = @{ Identity = $Upn } } }
            @{ CmdletInput = @{ CmdletName = 'Get-MailboxAutoReplyConfiguration'; Parameters = @{ Identity = $Upn } } }
            @{ CmdletInput = @{ CmdletName = 'Get-InboxRule'; Parameters = @{ Mailbox = $Upn; IncludeHidden = $true } } }
            @{ CmdletInput = @{ CmdletName = 'Get-MailboxStatistics'; Parameters = @{ Identity = $Upn } } }
            @{ CmdletInput = @{ CmdletName = 'Get-MailboxPermission'; Parameters = @{ Identity = $Upn } } }
            @{ CmdletInput = @{ CmdletName = 'Get-RecipientPermission'; Parameters = @{ Identity = $Upn } } }
            @{ CmdletInput = @{ CmdletName = 'Get-MailboxFolderStatistics'; Parameters = @{ Identity = $Upn; FolderScope = 'Calendar' } } }
        )
        $Exo = New-ExoBulkRequest -tenantid $TenantFilter -ReturnWithCommand $true -Anchor $Upn -cmdletArray $MailboxCmdlets
        if (-not $Exo) { $Exo = @{} }
        $Mailbox = @($Exo['Get-Mailbox'])[0]
        if (-not $Mailbox) { throw 'Exchange returned no response for the mailbox.' }

        if ($null -ne $Mailbox.PSObject.Properties['error']) {
            $MailboxError = Get-CIPPBecErrorInfo -Message ([string]$Mailbox.error)
            if (-not $MailboxError.Skipped) { throw $MailboxError.Message }
            $Findings.Add([pscustomobject]@{
                    Id = 'NoMailbox'; Category = 'Mailbox'; Title = 'No mailbox'
                    Detail = 'The user has no Exchange Online mailbox. One is created when a licence with Exchange Online is assigned.'
                    Note = 'Report only'; Fix = $null
                })
        } else {
            # A cmdlet that failed comes back as a single row carrying 'error'.
            $CheckNames = @{
                'Get-MailboxAutoReplyConfiguration' = 'Out of office'
                'Get-InboxRule'                     = 'Inbox rules'
                'Get-MailboxStatistics'             = 'Mailbox size'
                'Get-MailboxPermission'             = 'Mailbox permissions'
                'Get-RecipientPermission'           = 'Send As permissions'
                'Get-MailboxFolderStatistics'       = 'Calendar permissions'
            }
            $Rows = @{}
            foreach ($Cmdlet in $CheckNames.Keys) {
                $CmdletRows = @($Exo[$Cmdlet] | Where-Object { $_ })
                if ($CmdletRows.Count -gt 0 -and $null -ne $CmdletRows[0].PSObject.Properties['error']) {
                    $Errors.Add(@{ Check = $CheckNames[$Cmdlet]; Message = (Get-CIPPBecErrorInfo -Message ([string]$CmdletRows[0].error)).Message })
                    $CmdletRows = @()
                }
                $Rows[$Cmdlet] = $CmdletRows
            }

            $IsShared = $Mailbox.RecipientTypeDetails -eq 'SharedMailbox'
            if ($IsShared) {
                $Findings.Add([pscustomobject]@{
                        Id = 'SharedMailbox'; Category = 'Mailbox'; Title = 'Mailbox is a shared mailbox'
                        Detail = 'The mailbox was converted to a shared mailbox. Convert it back so the user can sign in to it with their own licence.'; Note = $null
                        Fix = @{ Key = 'ConvertToUserMailbox'; Label = 'Convert to user mailbox'; Default = $true; Params = @{} }
                    })
            }
            if ($Mailbox.HiddenFromAddressListsEnabled -eq $true) {
                $Findings.Add([pscustomobject]@{
                        Id = 'HiddenFromGAL'; Category = 'Mailbox'; Title = 'Hidden from the address list'
                        Detail = 'Colleagues cannot find the user in the global address list.'; Note = $null
                        Fix = @{ Key = 'UnhideFromGAL'; Label = 'Show in address list'; Default = $true; Params = @{} }
                    })
            }
            $ForwardTarget = if ($Mailbox.ForwardingSmtpAddress) { [string]$Mailbox.ForwardingSmtpAddress -replace '^smtp:', '' } else { [string]$Mailbox.ForwardingAddress }
            # Exchange reports an internal forwarding target by object id; show who it is.
            if ($ForwardTarget -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
                try {
                    $ForwardUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($ForwardTarget)?`$select=displayName,userPrincipalName" -tenantid $TenantFilter
                    if ($ForwardUser.userPrincipalName) { $ForwardTarget = "$($ForwardUser.displayName) ($($ForwardUser.userPrincipalName))" }
                } catch {
                    Write-Information "Could not resolve the forwarding target $ForwardTarget"
                }
            }
            if ($ForwardTarget) {
                $Findings.Add([pscustomobject]@{
                        Id = 'ForwardingSet'; Category = 'Mailbox'; Title = 'Email is forwarded'
                        Detail = "Mail sent to this mailbox is forwarded to $ForwardTarget."; Note = $null
                        Fix = @{ Key = 'RemoveForwarding'; Label = 'Remove forwarding'; Default = $true; Params = @{} }
                    })
            }
            $AutoReply = $Rows['Get-MailboxAutoReplyConfiguration'][0]
            if ($AutoReply.AutoReplyState -and $AutoReply.AutoReplyState -ne 'Disabled') {
                $Findings.Add([pscustomobject]@{
                        Id = 'OutOfOfficeOn'; Category = 'Mailbox'; Title = 'Out of office is on'
                        Detail = 'Automatic replies are being sent from this mailbox.'; Note = $null
                        Fix = @{ Key = 'DisableOutOfOffice'; Label = 'Turn off out of office'; Default = $true; Params = @{} }
                    })
            }
            $InboxRules = @($Rows['Get-InboxRule'] | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' })
            if ($InboxRules.Count -gt 0) {
                $ForwardingRules = @($InboxRules | Where-Object { $_.ForwardTo -or $_.ForwardAsAttachmentTo -or $_.RedirectTo })
                $RuleDetail = if ($ForwardingRules.Count -gt 0) {
                    "The mailbox has $($InboxRules.Count) inbox rule(s). $($ForwardingRules.Count) of them forward or redirect mail: $(@($ForwardingRules.Name) -join ', ')."
                } else {
                    "The mailbox has $($InboxRules.Count) inbox rule(s). None forward or redirect mail."
                }
                $Findings.Add([pscustomobject]@{ Id = 'InboxRules'; Category = 'Mailbox'; Title = 'Inbox rules exist'; Detail = $RuleDetail; Note = 'Report only'; Fix = $null })
            }
            if ($IsShared -and -not $Licensed -and $Rows['Get-MailboxStatistics'].Count -gt 0) {
                $MailboxBytes = try { Get-ExoOnlineStringBytes -SizeString ([string]$Rows['Get-MailboxStatistics'][0].TotalItemSize) } catch { 0 }
                if ($MailboxBytes -gt 50GB) {
                    $Findings.Add([pscustomobject]@{
                            Id = 'SharedOverQuota'; Category = 'Mailbox'; Title = 'Shared mailbox is over 50 GB without a licence'
                            Detail = "The mailbox holds $([math]::Round($MailboxBytes / 1GB, 1)) GB. An unlicensed shared mailbox is limited to 50 GB, so it needs a licence."
                            Note = 'Report only'; Fix = $null
                        })
                }
            }

            # Mailbox delegates: FullAccess, SendAs and SendOnBehalf merged per delegate.
            $LocalPart = ($Upn -split '@')[0]
            $Delegates = [ordered]@{}
            $DelegateGrants = @(
                foreach ($Permission in $Rows['Get-MailboxPermission']) {
                    if ($Permission.IsInherited -ne $true -and [string]$Permission.Deny -ne 'True' -and $Permission.AccessRights -contains 'FullAccess') { , @([string]$Permission.User, 'FullAccess') }
                }
                foreach ($Permission in $Rows['Get-RecipientPermission']) {
                    if ($Permission.IsInherited -ne $true -and $Permission.AccessControlType -ne 'Deny' -and $Permission.AccessRights -contains 'SendAs') { , @([string]$Permission.Trustee, 'SendAs') }
                }
            )
            # GrantSendOnBehalfTo holds directory object ids; show and merge them by UPN.
            $OnBehalf = @($Mailbox.GrantSendOnBehalfTo | Where-Object { $_ } | ForEach-Object { [string]$_ })
            $OnBehalfIds = @($OnBehalf | Where-Object { $_ -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' })
            $OnBehalfUpn = @{}
            if ($OnBehalfIds.Count -gt 0) {
                try {
                    $OnBehalfRequests = @($OnBehalfIds | ForEach-Object { @{ id = $_; method = 'GET'; url = "users/$($_)?`$select=id,userPrincipalName" } })
                    $OnBehalfResponses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $OnBehalfRequests)
                    foreach ($Response in $OnBehalfResponses) {
                        if ($Response.status -eq 200 -and $Response.body.userPrincipalName) { $OnBehalfUpn[[string]$Response.id] = [string]$Response.body.userPrincipalName }
                    }
                } catch {
                    Write-Information "Onboarding scan: could not resolve send-on-behalf delegates: $($_.Exception.Message)"
                }
            }
            $DelegateGrants = @($DelegateGrants; foreach ($Trustee in $OnBehalf) { , @(($OnBehalfUpn[$Trustee] ?? $Trustee), 'SendOnBehalf') })
            foreach ($Grant in $DelegateGrants) {
                $Trustee = $Grant[0]
                if (-not $Trustee -or $Trustee -match 'NT AUTHORITY\\SELF' -or $Trustee -eq 'S-1-5-10' -or $Trustee -eq $Upn -or $Trustee -eq $LocalPart -or $Trustee -eq $User.id) { continue }
                if (-not $Delegates.Contains($Trustee)) { $Delegates[$Trustee] = [System.Collections.Generic.List[string]]::new() }
                if (-not $Delegates[$Trustee].Contains($Grant[1])) { $Delegates[$Trustee].Add($Grant[1]) }
            }
            foreach ($Trustee in $Delegates.Keys) {
                $Rights = $Delegates[$Trustee].ToArray()
                $Findings.Add([pscustomobject]@{
                        Id = "MailboxDelegate:$Trustee"; Category = 'Delegated access'; Title = "$Trustee has access to the mailbox"
                        Detail = "$Trustee holds $($Rights -join ', ') on this mailbox."; Note = $null
                        Fix = @{ Key = 'RemoveMailboxPermissions'; Label = 'Remove mailbox access'; Default = $true; Params = @{ Items = @(@{ User = $Trustee; AccessRights = $Rights }) } }
                    })
            }

            # Calendar delegates. FolderType stays English whatever the mailbox language; the folder name does not.
            $CalendarFolder = $Rows['Get-MailboxFolderStatistics'] | Where-Object { $_.FolderType -eq 'Calendar' } | Select-Object -First 1
            if ($CalendarFolder.Name) {
                try {
                    $FolderIdentity = "$($Upn):\$($CalendarFolder.Name)"
                    $CalendarPermissions = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $Upn -cmdParams @{ Identity = $FolderIdentity } -UseSystemMailbox $true -Select 'Identity,User,AccessRights,FolderName')
                    $CalendarPermissions = @($CalendarPermissions | Where-Object { $_.User -and [string]$_.User -notin 'Default', 'Anonymous' })
                    if ($CalendarPermissions.Count -gt 0) {
                        # Exchange names grantees by display name; UserId is the unique id a removal needs.
                        $CalendarPermissions = @(Resolve-CIPPFolderPermissionUser -TenantFilter $TenantFilter -FolderIdentity $FolderIdentity -Permissions $CalendarPermissions)
                    }
                    foreach ($Permission in $CalendarPermissions) {
                        $Grantee = [string]$Permission.User
                        $Findings.Add([pscustomobject]@{
                                Id = "CalendarDelegate:$Grantee"; Category = 'Delegated access'; Title = "$Grantee has access to the calendar"
                                Detail = "$Grantee holds $(@($Permission.AccessRights) -join ', ') on the $($CalendarFolder.Name) folder."; Note = $null
                                Fix = @{ Key = 'RemoveCalendarPermissions'; Label = 'Remove calendar access'; Default = $true; Params = @{ Items = @(@{ User = [string]($Permission.UserId ?? $Grantee); Name = [string]$Grantee; FolderName = [string]$CalendarFolder.Name }) } }
                            })
                    }
                } catch {
                    $Errors.Add(@{ Check = 'Calendar permissions'; Message = (Get-CippException -Exception $_).NormalizedError })
                }
            }
        }
    } catch {
        $Errors.Add(@{ Check = 'Mailbox'; Message = (Get-CippException -Exception $_).NormalizedError })
    }

    # OneDrive site collection admins other than the owner. No drive means no OneDrive, which is not an error.
    $OneDriveError = $null
    $SiteUrl = if ($AppOnly['drive'].status -eq 200) { [string]$AppOnly['drive'].body.sharepointIds.siteUrl }
    if ($SiteUrl) {
        try {
            $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
            $Admins = @(New-GraphGetRequest -uri "$($RestContext.BaseUri)/web/siteusers?`$filter=IsSiteAdmin eq true&`$select=Id,Title,Email,LoginName,PrincipalType" -tenantid $TenantFilter -scope $RestContext.Scope -extraHeaders $RestContext.Headers -UseCertificate -AsApp $true)
            foreach ($Admin in $Admins) {
                if ($Admin.PrincipalType -ne 1) { continue }
                $AdminUpn = ([string]$Admin.LoginName -split '\|')[-1]
                if ([string]::IsNullOrWhiteSpace($AdminUpn) -or $AdminUpn -like 'SHAREPOINT\*' -or $AdminUpn -like 'app@sharepoint' -or $AdminUpn -eq $Upn) { continue }
                $Findings.Add([pscustomobject]@{
                        Id = "OneDriveSiteAdmin:$AdminUpn"; Category = 'Delegated access'; Title = "$AdminUpn has full access to the OneDrive"
                        Detail = "$AdminUpn is a site collection admin of the user's OneDrive."; Note = $null
                        Fix = @{ Key = 'RemoveOneDriveSiteAdmins'; Label = 'Remove OneDrive access'; Default = $true; Params = @{ Items = @(@{ User = $AdminUpn }) } }
                    })
            }
        } catch {
            $OneDriveError = (Get-CippException -Exception $_).NormalizedError
        }
    } elseif ($AppOnly['drive'] -and $AppOnly['drive'].status -notin 200, 404) {
        $OneDriveError = [string]($AppOnly['drive'].body.error.message ?? "HTTP $($AppOnly['drive'].status)")
    }
    # SharePoint locks the OneDrive of an unlicensed user; that is expected here, not a failed check.
    if ($OneDriveError -match 'site has been blocked') {
        $Findings.Add([pscustomobject]@{
                Id = 'OneDriveLocked'; Category = 'Delegated access'; Title = 'OneDrive is locked'
                Detail = 'The OneDrive is locked, usually because the user has no licence. Who has access to it can be checked once a licence is assigned.'
                Note = 'Report only'; Fix = $null
            })
    } elseif ($OneDriveError) {
        $Errors.Add(@{ Check = 'OneDrive access'; Message = $OneDriveError })
    }
    #endregion Mailbox and delegated access

    #region Entitlements
    if (-not $Licensed) {
        $Findings.Add([pscustomobject]@{ Id = 'NoLicenses'; Category = 'Entitlements'; Title = 'No licences assigned'; Detail = 'The user has no licences. Choose them on the next step.'; Note = 'Next step'; Fix = $null })
    }
    $CurrentGroupIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Core['groups'].status -ne 200) {
        $Errors.Add(@{ Check = 'Groups'; Message = [string]($Core['groups'].body.error.message ?? "HTTP $($Core['groups'].status)") })
    } else {
        foreach ($Group in @($Core['groups'].body.value)) { if ($Group.id) { $null = $CurrentGroupIds.Add([string]$Group.id) } }
        if ($CurrentGroupIds.Count -eq 0) {
            $Findings.Add([pscustomobject]@{ Id = 'NoGroups'; Category = 'Entitlements'; Title = 'Not a member of any group'; Detail = 'The user is in no groups. Choose them on the next step.'; Note = 'Next step'; Fix = $null })
        }
    }
    if ($Core['devices'].status -ne 200) {
        $Errors.Add(@{ Check = 'Devices'; Message = [string]($Core['devices'].body.error.message ?? "HTTP $($Core['devices'].status)") })
    } elseif (@($Core['devices'].body.value).Count -eq 0) {
        $Findings.Add([pscustomobject]@{ Id = 'NoDevices'; Category = 'Entitlements'; Title = 'No devices'; Detail = 'No devices are registered to the user.'; Note = 'Report only'; Fix = $null })
    }

    $Snapshot = $null
    try {
        $CustomerId = @(Get-Tenants -TenantFilter $TenantFilter)[0].customerId
        $Table = Get-CIPPTable -TableName 'OffboardingSnapshots'
        $Row = if ($CustomerId) { Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$(ConvertTo-CIPPODataFilterValue -Value $CustomerId)' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $User.id)'" | Select-Object -First 1 }
        if ($Row.Snapshot) {
            $Saved = $Row.Snapshot | ConvertFrom-Json

            if ($Core['skus'].status -ne 200) {
                $Errors.Add(@{ Check = 'Licence availability'; Message = [string]($Core['skus'].body.error.message ?? "HTTP $($Core['skus'].status)") })
            }
            $Skus = @($Core['skus'].body.value)
            $SnapshotLicenses = @(foreach ($License in @($Saved.Licenses)) {
                    $Sku = $Skus | Where-Object { $_.skuId -eq $License.skuId } | Select-Object -First 1
                    $Available = if ($Sku) { [math]::Max(0, [int]$Sku.prepaidUnits.enabled - [int]$Sku.consumedUnits) } else { 0 }
                    [pscustomobject]@{ skuId = $License.skuId; skuPartNumber = $License.skuPartNumber; displayName = $License.displayName; available = $Available }
                })

            $SavedGroups = @($Saved.Groups | Where-Object { $_.id })
            $LiveGroups = @{}
            if ($SavedGroups.Count -gt 0) {
                $GroupRequests = @($SavedGroups | ForEach-Object { @{ id = [string]$_.id; method = 'GET'; url = "groups/$($_.id)?`$select=id,displayName,onPremisesSyncEnabled,membershipRule" } })
                $GroupResponses = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $GroupRequests)
                foreach ($Response in $GroupResponses) {
                    $LiveGroups[[string]$Response.id] = $Response
                }
            }
            $SnapshotGroups = @(foreach ($Group in $SavedGroups) {
                    $Live = $LiveGroups[[string]$Group.id]
                    $SkipReason = if ($Live.status -eq 404) { 'This group has been deleted since the offboarding.' }
                    elseif ($Live.status -ne 200) { 'Failed to check this group, so it cannot be restored now.' }
                    elseif ($CurrentGroupIds.Contains([string]$Group.id)) { 'The user is already a member of this group.' }
                    elseif (-not [string]::IsNullOrWhiteSpace($Live.body.membershipRule)) { 'This is a dynamic group. Its membership rule adds the user.' }
                    elseif ($Live.body.onPremisesSyncEnabled) { 'This group is synced from Active Directory. Add the user on-premises.' }
                    [pscustomobject]@{
                        id          = $Group.id
                        displayName = ($Live.body.displayName ?? $Group.displayName)
                        groupType   = $Group.groupType
                        restorable  = -not $SkipReason
                        skipReason  = $SkipReason
                    }
                })

            # Only an account that had an immutable ID before offboarding can have had it cleared.
            if ($Saved.HadImmutableId -eq $true -and [string]::IsNullOrEmpty($User.onPremisesImmutableId)) {
                $Findings.Add([pscustomobject]@{
                        Id = 'ImmutableIdCleared'; Category = 'Account'; Title = 'Immutable ID was cleared'
                        Detail = 'The account was linked to an on-premises Active Directory account before the offboarding and no longer is.'
                        Note = 'Report only'; Fix = $null
                    })
            }

            $SavedRoles = @($Saved.Roles | Where-Object { $_.id })
            if ($SavedRoles.Count -gt 0) {
                try {
                    $HeldRoleIds = @((Get-CIPPPIMRoleAssignments -TenantFilter $TenantFilter -PrincipalId $User.id).RoleDefinitionId)
                    $RemovedRoles = @($SavedRoles | Where-Object { $_.id -notin $HeldRoleIds })
                    if ($RemovedRoles.Count -gt 0) {
                        $Findings.Add([pscustomobject]@{
                                Id = 'RolesRemoved'; Category = 'Entitlements'; Title = 'Admin roles were removed'
                                Detail = "The user held these admin roles before the offboarding and no longer does: $(@($RemovedRoles.displayName) -join ', '). Roles are not restored automatically; assign them again if they are still needed."
                                Note = 'Report only'; Fix = $null
                            })
                    }
                } catch {
                    $Errors.Add(@{ Check = 'Admin roles'; Message = (Get-CippException -Exception $_).NormalizedError })
                }
            }

            $Snapshot = [pscustomobject]@{
                OffboardedAt = $Row.OffboardedAt
                Licenses     = $SnapshotLicenses
                Groups       = $SnapshotGroups
                Roles        = @($SavedRoles | ForEach-Object { [pscustomobject]@{ id = $_.id; displayName = $_.displayName } })
                Manager      = if ($Saved.Manager.id) { [pscustomobject]@{ id = $Saved.Manager.id; userPrincipalName = $Saved.Manager.userPrincipalName; displayName = $Saved.Manager.displayName } }
            }
        }
    } catch {
        $Errors.Add(@{ Check = 'Offboarding snapshot'; Message = (Get-CippException -Exception $_).NormalizedError })
    }
    #endregion Entitlements

    Write-LogMessage -headers $Headers -API 'Onboarding scan' -tenant $TenantFilter -message "Scanned $Upn for onboarding: $($Findings.Count) finding(s), $($Errors.Count) failed check(s)" -sev Debug

    # Grouped in the wizard's category order.
    $CategoryOrder = @('Account', 'Mailbox', 'Delegated access', 'Entitlements')
    return [pscustomobject]@{
        User     = [pscustomobject]@{
            id                    = $User.id
            userPrincipalName     = $Upn
            displayName           = $User.displayName
            accountEnabled        = $User.accountEnabled -eq $true
            deleted               = $false
            deletedDateTime       = $null
            onPremisesSyncEnabled = $IsSynced
        }
        Snapshot = $Snapshot
        Findings = @($Findings | Sort-Object -Stable -Property @{ Expression = { $CategoryOrder.IndexOf($_.Category) } })
        Errors   = $Errors.ToArray()
    }
}
