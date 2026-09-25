function Get-CIPPBecMailboxInventory {
    <#
    .SYNOPSIS
        Collects the mailbox's current state, its delegation inventory and its add-ins for the BEC check.
    .DESCRIPTION
        Two Exchange bulk rounds. Round one reads the mailbox (forwarding, send-on-behalf, audit state),
        the CAS mailbox (protocol flags), the auto-reply configuration (state, schedule and audience only
        - the reply text itself is never stored), FullAccess and SendAs permissions, the Calendar and
        Inbox folder ids (display names are locale-dependent) and the mailbox add-ins. Round two reads
        the folder permissions for those folder ids and, for room/equipment mailboxes, the resource
        delegates.

        Every sub-request is stamped with an OperationGuid and validated individually: New-ExoBulkRequest
        swallows transport failures, so a missing or errored part is reported as incomplete rather than
        read as "no delegations".
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The investigated mailbox.
    .PARAMETER Heuristics
        The BEC heuristics object.
    .PARAMETER AcceptedDomains
        The tenant's accepted domains, used to mark external trustees.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)]$Heuristics,
        [string[]]$AcceptedDomains = @()
    )

    $Upn = $UserPrincipalName
    $LocalPart = ($Upn -split '@')[0]
    $AcceptedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($AcceptedDomains | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }), [System.StringComparer]::OrdinalIgnoreCase)

    $Round1 = @(
        @{ CmdletInput = @{ CmdletName = 'Get-Mailbox'; Parameters = @{ Identity = $Upn } }; OperationGuid = 'Mailbox' }
        @{ CmdletInput = @{ CmdletName = 'Get-CASMailbox'; Parameters = @{ Identity = $Upn } }; OperationGuid = 'CAS' }
        @{ CmdletInput = @{ CmdletName = 'Get-MailboxAutoReplyConfiguration'; Parameters = @{ Identity = $Upn } }; OperationGuid = 'AutoReply' }
        @{ CmdletInput = @{ CmdletName = 'Get-MailboxPermission'; Parameters = @{ Identity = $Upn } }; OperationGuid = 'MailboxPermission' }
        @{ CmdletInput = @{ CmdletName = 'Get-RecipientPermission'; Parameters = @{ Identity = $Upn } }; OperationGuid = 'RecipientPermission' }
        @{ CmdletInput = @{ CmdletName = 'Get-App'; Parameters = @{ Mailbox = $Upn } }; OperationGuid = 'Apps' }
        foreach ($Scope in @($Heuristics.delegations.folderScopes)) {
            @{ CmdletInput = @{ CmdletName = 'Get-MailboxFolderStatistics'; Parameters = @{ Identity = $Upn; FolderScope = $Scope } }; OperationGuid = "FolderStats-$Scope" }
        }
    )

    $Bulk = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Round1) -ReturnWithCommand $true -Anchor $Upn
    if (-not $Bulk) { $Bulk = @{} }

    # Pull one operation's rows out of the cmdlet-keyed bulk result; $null when the request never came back.
    $GetOp = {
        param($Cmdlet, $Guid)
        $Rows = @($Bulk[$Cmdlet] | Where-Object { $_.OperationGuid -eq $Guid })
        if ($Rows.Count -eq 0) { return $null }
        if ($Rows[0].PSObject.Properties['error']) { throw [string]$Rows[0].error }
        return @($Rows | Where-Object { -not $_.PSObject.Properties['Success'] -or $_.PSObject.Properties.Count -gt 2 })
    }
    $Errors = @{}
    $Fetch = {
        param($Name, $Cmdlet, $Guid)
        try {
            $Rows = & $GetOp $Cmdlet $Guid
            if ($null -eq $Rows) { $Errors[$Name] = "$Cmdlet returned no response"; return @() }
            return $Rows
        } catch {
            $Errors[$Name] = "$Cmdlet`: $($_.Exception.Message)"
            return @()
        }
    }

    $Mailbox = @(& $Fetch 'Mailbox' 'Get-Mailbox' 'Mailbox') | Select-Object -First 1
    $Cas = @(& $Fetch 'CAS' 'Get-CASMailbox' 'CAS') | Select-Object -First 1
    $AutoReply = @(& $Fetch 'AutoReply' 'Get-MailboxAutoReplyConfiguration' 'AutoReply') | Select-Object -First 1
    $MailboxPermissions = @(& $Fetch 'MailboxPermission' 'Get-MailboxPermission' 'MailboxPermission')
    $RecipientPermissions = @(& $Fetch 'RecipientPermission' 'Get-RecipientPermission' 'RecipientPermission')
    $Apps = @(& $Fetch 'Apps' 'Get-App' 'Apps')
    $Folders = @(foreach ($Scope in @($Heuristics.delegations.folderScopes)) {
            @(& $Fetch "FolderStats-$Scope" 'Get-MailboxFolderStatistics' "FolderStats-$Scope") | Where-Object { $_.FolderType -eq $Scope -and $_.FolderId } | Select-Object -First 1
        })

    $IsResource = $Mailbox.RecipientTypeDetails -in @('RoomMailbox', 'EquipmentMailbox')
    $Round2 = @(
        foreach ($Folder in $Folders) {
            @{ CmdletInput = @{ CmdletName = 'Get-MailboxFolderPermission'; Parameters = @{ Identity = "$($Upn):$($Folder.FolderId)" } }; OperationGuid = "FolderPermission-$($Folder.FolderType)" }
        }
        if ($IsResource) {
            @{ CmdletInput = @{ CmdletName = 'Get-CalendarProcessing'; Parameters = @{ Identity = $Upn } }; OperationGuid = 'CalendarProcessing' }
        }
    )
    $FolderPermissions = @{}
    $ResourceDelegates = @()
    if ($Round2.Count -gt 0) {
        $Bulk = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Round2) -ReturnWithCommand $true -Anchor $Upn
        if (-not $Bulk) { $Bulk = @{} }
        foreach ($Folder in $Folders) {
            $FolderPermissions[$Folder.FolderType] = @(& $Fetch "FolderPermission-$($Folder.FolderType)" 'Get-MailboxFolderPermission' "FolderPermission-$($Folder.FolderType)")
        }
        if ($IsResource) {
            $Processing = @(& $Fetch 'CalendarProcessing' 'Get-CalendarProcessing' 'CalendarProcessing') | Select-Object -First 1
            $ResourceDelegates = @($Processing.ResourceDelegates | Where-Object { $_ })
        }
    }

    # A trustee is flagged when it is a guest, an address outside the accepted domains, or a
    # catch-all folder principal with more than availability rights.
    $TrusteeFlag = {
        param($Trustee)
        $T = [string]$Trustee
        if ([string]::IsNullOrWhiteSpace($T)) { return $false }
        if ($T -match '#EXT#') { return $true }
        if ($T -match '@') {
            $Domain = ($T -split '@')[-1].Trim().ToLowerInvariant()
            if ($AcceptedSet.Count -gt 0 -and -not $AcceptedSet.Contains($Domain)) { return $true }
        }
        return $false
    }
    $IsSelf = { param($Trustee) $T = [string]$Trustee; ($T -match 'NT AUTHORITY\\SELF') -or ($T -eq 'S-1-5-10') -or ($T -ieq $Upn) -or ($T -ieq $LocalPart) }

    # Identity is what a removal needs to send back to Exchange: the mailbox for mailbox-level
    # rights, and mailbox:<FolderId> for folder rights (folder display names are locale-dependent).
    $Delegations = [System.Collections.Generic.List[object]]::new()
    foreach ($Permission in $MailboxPermissions) {
        if ($Permission.IsInherited -eq $true -or (& $IsSelf $Permission.User)) { continue }
        $Delegations.Add([pscustomobject]@{
                PermissionType = 'FullAccess'
                Resource       = $Upn
                Identity       = $Upn
                Trustee        = [string]$Permission.User
                AccessRights   = @($Permission.AccessRights) -join ', '
                Deny           = ([string]$Permission.Deny -eq 'True')
                Flagged        = (& $TrusteeFlag $Permission.User)
            })
    }
    foreach ($Permission in $RecipientPermissions) {
        if ($Permission.IsInherited -eq $true -or (& $IsSelf $Permission.Trustee)) { continue }
        $Delegations.Add([pscustomobject]@{
                PermissionType = 'SendAs'
                Resource       = $Upn
                Identity       = $Upn
                Trustee        = [string]$Permission.Trustee
                AccessRights   = @($Permission.AccessRights) -join ', '
                Deny           = ($Permission.AccessControlType -eq 'Deny')
                Flagged        = (& $TrusteeFlag $Permission.Trustee)
            })
    }
    foreach ($Trustee in @($Mailbox.GrantSendOnBehalfTo | Where-Object { $_ })) {
        $Delegations.Add([pscustomobject]@{
                PermissionType = 'SendOnBehalf'
                Resource       = $Upn
                Identity       = $Upn
                Trustee        = [string]$Trustee
                AccessRights   = 'SendOnBehalf'
                Deny           = $false
                Flagged        = (& $TrusteeFlag $Trustee)
            })
    }
    foreach ($FolderType in $FolderPermissions.Keys) {
        $Folder = $Folders | Where-Object { $_.FolderType -eq $FolderType } | Select-Object -First 1
        foreach ($Permission in $FolderPermissions[$FolderType]) {
            $User = [string]($Permission.User.DisplayName ?? $Permission.User)
            $Rights = @($Permission.AccessRights) -join ', '
            $IsCatchAll = $User -in @('Default', 'Anonymous')
            if ($IsCatchAll -and ($Rights -in @('None', 'AvailabilityOnly', 'LimitedDetails') -or [string]::IsNullOrWhiteSpace($Rights))) { continue }
            if ((& $IsSelf $User)) { continue }
            $Delegations.Add([pscustomobject]@{
                    PermissionType = 'Folder'
                    Resource       = "$Upn`:\$FolderType"
                    Identity       = "$($Upn):$($Folder.FolderId)"
                    Trustee        = $User
                    AccessRights   = $Rights
                    Deny           = $false
                    Flagged        = ($IsCatchAll -or (& $TrusteeFlag $User) -or (& $TrusteeFlag $Permission.User.ADRecipient.PrimarySmtpAddress))
                })
        }
    }
    foreach ($Delegate in $ResourceDelegates) {
        $Delegations.Add([pscustomobject]@{
                PermissionType = 'ResourceDelegate'
                Resource       = $Upn
                Identity       = $Upn
                Trustee        = [string]$Delegate
                AccessRights   = 'ResourceDelegate'
                Deny           = $false
                Flagged        = (& $TrusteeFlag $Delegate)
            })
    }

    $TrustedProvider = [string]$Heuristics.mailboxAddIns.trustedProviderRegex
    $AddIns = @(foreach ($App in $Apps) {
            if (-not $App.DisplayName -and -not $App.AppId) { continue }
            $Provider = [string]$App.ProviderName
            $UserScoped = -not ($App.Scope -eq 'Organization')
            [pscustomobject]@{
                Identity           = $App.Identity
                DisplayName        = $App.DisplayName
                AppId              = $App.AppId
                Enabled            = ([string]$App.Enabled -eq 'True')
                ProviderName       = $Provider
                AppVersion         = $App.AppVersion
                Type               = $App.Type
                Scope              = $App.Scope
                DefaultStateForUser = $App.DefaultStateForUser
                MarketplaceAssetId = $App.MarketplaceAssetId
                Flagged            = (([string]$App.Enabled -eq 'True') -and $UserScoped -and -not ($TrustedProvider -and $Provider -match $TrustedProvider))
            }
        })

    $MailboxState = if ($Mailbox) {
        [pscustomobject]@{
            PrimarySmtpAddress            = $Mailbox.PrimarySmtpAddress
            RecipientTypeDetails          = $Mailbox.RecipientTypeDetails
            ExternalDirectoryObjectId     = $Mailbox.ExternalDirectoryObjectId
            ForwardingAddress             = [string]$Mailbox.ForwardingAddress
            ForwardingSmtpAddress         = [string]$Mailbox.ForwardingSmtpAddress
            DeliverToMailboxAndForward    = ([string]$Mailbox.DeliverToMailboxAndForward -eq 'True')
            HasForwarding                 = [bool]($Mailbox.ForwardingAddress -or $Mailbox.ForwardingSmtpAddress)
            GrantSendOnBehalfTo           = @($Mailbox.GrantSendOnBehalfTo | Where-Object { $_ } | ForEach-Object { [string]$_ })
            AuditEnabled                  = $Mailbox.AuditEnabled
            LitigationHoldEnabled         = $Mailbox.LitigationHoldEnabled
            HiddenFromAddressListsEnabled = $Mailbox.HiddenFromAddressListsEnabled
            WhenMailboxCreated            = $Mailbox.WhenMailboxCreated
            AutoReplyState                = $AutoReply.AutoReplyState
            AutoReplyStartTime            = $AutoReply.StartTime
            AutoReplyEndTime              = $AutoReply.EndTime
            AutoReplyExternalAudience     = $AutoReply.ExternalAudience
            AutoReplyHasInternalMessage   = -not [string]::IsNullOrWhiteSpace([string]$AutoReply.InternalMessage)
            AutoReplyHasExternalMessage   = -not [string]::IsNullOrWhiteSpace([string]$AutoReply.ExternalMessage)
            OWAEnabled                    = $Cas.OWAEnabled
            ECPEnabled                    = $Cas.ECPEnabled
            EWSEnabled                    = $Cas.EWSEnabled
            IMAPEnabled                   = $Cas.IMAPEnabled
            POPEnabled                    = $Cas.POPEnabled
            MAPIEnabled                   = $Cas.MAPIEnabled
            ActiveSyncEnabled             = $Cas.ActiveSyncEnabled
            SmtpClientAuthenticationDisabled = $Cas.SmtpClientAuthenticationDisabled
            ActiveSyncBlockedDeviceIDs    = @($Cas.ActiveSyncBlockedDeviceIDs | Where-Object { $_ })
        }
    } else { $null }

    $StateErrors = @('Mailbox', 'CAS', 'AutoReply') | Where-Object { $Errors.ContainsKey($_) } | ForEach-Object { $Errors[$_] }
    $DelegationErrorKeys = @('MailboxPermission', 'RecipientPermission', 'CalendarProcessing') + @($Errors.Keys | Where-Object { $_ -like 'FolderStats-*' -or $_ -like 'FolderPermission-*' })
    $DelegationErrors = @($DelegationErrorKeys | Select-Object -Unique | Where-Object { $Errors.ContainsKey($_) } | ForEach-Object { $Errors[$_] })
    $AddInErrors = @(if ($Errors.ContainsKey('Apps')) { $Errors['Apps'] })

    return [pscustomobject]@{
        MailboxState = New-CIPPBecCollectorResult -Data $MailboxState -Complete ($StateErrors.Count -eq 0 -and $null -ne $Mailbox) -Error ($(if ($StateErrors.Count -gt 0) { $StateErrors -join '; ' } elseif (-not $Mailbox) { 'Get-Mailbox returned no mailbox' } else { $null })) -Count ($(if ($Mailbox) { 1 } else { 0 }))
        Delegations  = New-CIPPBecCollectorResult -Data @($Delegations | Sort-Object -Property @{ Expression = { $_.Flagged }; Descending = $true }, PermissionType, Trustee) -Complete ($DelegationErrors.Count -eq 0) -Error ($(if ($DelegationErrors.Count -gt 0) { $DelegationErrors -join '; ' } else { $null }))
        AddIns       = New-CIPPBecCollectorResult -Data @($AddIns | Sort-Object -Property @{ Expression = { $_.Flagged }; Descending = $true }, DisplayName) -Complete ($AddInErrors.Count -eq 0) -Error ($(if ($AddInErrors.Count -gt 0) { $AddInErrors -join '; ' } else { $null }))
    }
}
