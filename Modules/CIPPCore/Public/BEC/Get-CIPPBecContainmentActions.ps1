function Get-CIPPBecContainmentActions {
    <#
    .SYNOPSIS
        Returns the catalog of BEC containment actions.
    .DESCRIPTION
        The single source of truth for what Invoke-CIPPBecContainment can do: id, label, what it does,
        impact (Low/Medium/High/Critical), whether it is reversible, whether it runs by default (the
        built-in set below, overridden by the instance-wide defaults saved from CIPP settings via
        ExecBECRemediationDefaults), the order the dispatcher runs it in, and the
        parameter it reads its explicit targets from. Critical actions need a typed confirmation from
        an operator; automation (the webhook action) passes -Confirmed instead. Release says what
        Invoke-CIPPBecRelease does with it: Reverse lifts a lockout on the legitimate user, Keep leaves
        attacker cleanup in place, and Manual is listed for the operator because it cannot be undone
        or is not automated. The frontend renders
        this list, so labels and descriptions are operator-facing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Catalog = @(
        [pscustomobject]@{ Id = 'ResetPassword'; Label = 'Reset password'; Description = 'Sets a new random password (shown once, or as a PwPush link) and requires a change at next sign-in.'; Impact = 'Critical'; Reversible = $false; DefaultSelected = $true; Order = 1; TargetSource = $null; ParameterName = $null; Release = 'Manual' }
        [pscustomobject]@{ Id = 'DisableAccount'; Label = 'Block sign-in'; Description = 'Disables the account in Entra ID. Directory-synced accounts must also be disabled on-premises or the sync will re-enable them.'; Impact = 'Critical'; Reversible = $true; DefaultSelected = $true; Order = 2; TargetSource = $null; ParameterName = $null; Release = 'Reverse' }
        [pscustomobject]@{ Id = 'RevokeSessions'; Label = 'Revoke sessions'; Description = 'Invalidates every refresh token so existing sessions and stolen tokens stop working.'; Impact = 'High'; Reversible = $false; DefaultSelected = $true; Order = 3; TargetSource = $null; ParameterName = $null; Release = 'Manual' }
        [pscustomobject]@{ Id = 'RemoveMFA'; Label = 'Remove MFA methods'; Description = 'Removes the selected authentication methods, or every method when none is selected, so an attacker-registered method cannot be used to get back in.'; Impact = 'High'; Reversible = $false; DefaultSelected = $true; Order = 4; TargetSource = 'MFADevices'; ParameterName = 'MfaMethodIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'RemoveOAuthGrants'; Label = 'Revoke application consents'; Description = 'Deletes the selected OAuth consent grants and app-role assignments (flagged ones by default). Consent survives a password reset.'; Impact = 'Critical'; Reversible = $false; DefaultSelected = $false; Order = 5; TargetSource = 'UserGrants'; ParameterName = 'GrantIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'DisableServicePrincipals'; Label = 'Disable rogue applications tenant-wide'; Description = 'Disables the service principal of every application that matched the rogue-app catalogs, for all users. Re-enable it from the enterprise applications page if it turns out to be legitimate.'; Impact = 'Critical'; Reversible = $true; DefaultSelected = $false; Order = 6; TargetSource = 'UserGrants'; ParameterName = 'ServicePrincipalIds'; Release = 'Keep' }
        [pscustomobject]@{ Id = 'DisableInboxRules'; Label = 'Disable inbox rules'; Description = 'Disables every inbox rule on the mailbox except the junk and out-of-office system rules, or only the selected ones.'; Impact = 'High'; Reversible = $true; DefaultSelected = $true; Order = 7; TargetSource = 'NewRules'; ParameterName = 'RuleIds'; Release = 'Keep' }
        [pscustomobject]@{ Id = 'ClearForwarding'; Label = 'Clear mailbox forwarding'; Description = 'Removes the mailbox forwarding address and SMTP forwarding address.'; Impact = 'High'; Reversible = $true; DefaultSelected = $false; Order = 8; TargetSource = 'MailboxState'; ParameterName = $null; Release = 'Keep' }
        [pscustomobject]@{ Id = 'ClearAutoReply'; Label = 'Turn off automatic replies'; Description = 'Disables the out-of-office auto-reply, a common diversion once a mailbox is taken over.'; Impact = 'Medium'; Reversible = $true; DefaultSelected = $false; Order = 9; TargetSource = 'MailboxState'; ParameterName = $null; Release = 'Keep' }
        [pscustomobject]@{ Id = 'RemoveDelegations'; Label = 'Remove mailbox delegations'; Description = 'Removes the selected FullAccess, SendAs, SendOnBehalf, folder and resource-delegate permissions (flagged ones by default).'; Impact = 'Critical'; Reversible = $true; DefaultSelected = $false; Order = 10; TargetSource = 'Delegations'; ParameterName = 'Delegations'; Release = 'Keep' }
        [pscustomobject]@{ Id = 'DisableTransportRules'; Label = 'Disable transport rules'; Description = 'Disables the selected tenant-wide transport rules (by default the flagged ones changed in the window). Affects every mailbox in the tenant.'; Impact = 'Critical'; Reversible = $true; DefaultSelected = $false; Order = 11; TargetSource = 'TransportRulesFlagged'; ParameterName = 'TransportRuleIds'; Release = 'Keep' }
        [pscustomobject]@{ Id = 'DisableMailboxAddIns'; Label = 'Disable mailbox add-ins'; Description = 'Disables the selected add-ins for this mailbox (flagged user-installed ones by default).'; Impact = 'Medium'; Reversible = $true; DefaultSelected = $false; Order = 12; TargetSource = 'MailboxAddIns'; ParameterName = 'AddInIds'; Release = 'Keep' }
        [pscustomobject]@{ Id = 'BlockProtocols'; Label = 'Block legacy mailbox protocols'; Description = 'Turns off the selected client protocols on the mailbox (EWS, IMAP, POP, ActiveSync and SMTP AUTH by default; OWA, MAPI and ECP optional).'; Impact = 'High'; Reversible = $true; DefaultSelected = $true; Order = 13; TargetSource = 'MailboxState'; ParameterName = 'Protocols'; Release = 'Reverse' }
        [pscustomobject]@{ Id = 'BlockMobileDevices'; Label = 'Block mobile device partnerships'; Description = 'Adds the selected ActiveSync devices (all by default) to the mailbox block list.'; Impact = 'High'; Reversible = $true; DefaultSelected = $false; Order = 14; TargetSource = 'SuspectUserDevices'; ParameterName = 'MobileDeviceIds'; Release = 'Reverse' }
        [pscustomobject]@{ Id = 'RemoveMobileDevices'; Label = 'Remove mobile device partnerships'; Description = 'Deletes the selected ActiveSync device partnerships (all by default); the device must re-pair to sync again.'; Impact = 'High'; Reversible = $false; DefaultSelected = $false; Order = 15; TargetSource = 'SuspectUserDevices'; ParameterName = 'MobileDeviceIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'DisableRegisteredDevices'; Label = 'Disable registered devices'; Description = 'Disables the selected Entra devices (those registered in the window by default) so they can no longer satisfy device-based Conditional Access.'; Impact = 'High'; Reversible = $true; DefaultSelected = $false; Order = 16; TargetSource = 'RegisteredDevices'; ParameterName = 'RegisteredDeviceIds'; Release = 'Reverse' }
        [pscustomobject]@{ Id = 'RemoveRegisteredDevices'; Label = 'Delete registered devices'; Description = 'Deletes the selected Entra device objects (those registered in the window by default).'; Impact = 'Critical'; Reversible = $false; DefaultSelected = $false; Order = 17; TargetSource = 'RegisteredDevices'; ParameterName = 'RegisteredDeviceIds'; Release = 'Manual' }
        [pscustomobject]@{ Id = 'TargetedCAPolicy'; Label = 'Targeted Conditional Access policy'; Description = 'Creates a Conditional Access policy for this user only that requires MFA (optionally plus a compliant device) for every application, and schedules its removal after the chosen number of hours.'; Impact = 'High'; Reversible = $true; DefaultSelected = $false; Order = 18; TargetSource = $null; ParameterName = 'CAPolicy'; Release = 'Reverse' }
        [pscustomobject]@{ Id = 'DisableOneDriveSharing'; Label = 'Disable OneDrive sharing'; Description = "Sets the user's OneDrive sharing capability to disabled. Existing links are not removed."; Impact = 'Medium'; Reversible = $true; DefaultSelected = $false; Order = 19; TargetSource = 'SharingChanges'; ParameterName = $null; Release = 'Manual' }
        [pscustomobject]@{ Id = 'BlockSenders'; Label = 'Block phishing senders tenant-wide'; Description = 'Adds the phishing-shaped senders that reached this mailbox (from the received-mail findings) to the Tenant Allow/Block List as blocked senders, for every mailbox in the tenant. Reversible from the Tenant Allow/Block List page.'; Impact = 'Medium'; Reversible = $true; DefaultSelected = $false; Order = 20; TargetSource = 'ReceivedMailFindings'; ParameterName = 'BlockSenders'; Release = 'Keep' }
        [pscustomobject]@{ Id = 'RemoveSharingLinks'; Label = 'Remove OneDrive/SharePoint sharing links'; Description = 'Deletes the anonymous ("anyone") and company-wide sharing links the user created on OneDrive/SharePoint items in the window (from the sharing-change findings). Unlike disabling sharing, this revokes links that already exist and are the actual exposure. Not reversible - a removed link is gone, though it can be re-created.'; Impact = 'High'; Reversible = $false; DefaultSelected = $false; Order = 21; TargetSource = 'SharingChanges'; ParameterName = 'SharingLinkUrls'; Release = 'Manual' }
    )

    # Instance-wide defaults saved from CIPP settings replace the built-in DefaultSelected flags.
    # A missing row or a failed read keeps the built-in set.
    $Saved = try {
        $Table = Get-CIPPTable -TableName Settings
        (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'BecRemediation' and RowKey eq 'Defaults'").DefaultActions
    } catch { $null }
    if ($Saved) {
        $SavedIds = @($Saved | ConvertFrom-Json)
        foreach ($Action in $Catalog) { $Action.DefaultSelected = $Action.Id -in $SavedIds }
    }
    $Catalog
}
