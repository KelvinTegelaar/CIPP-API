BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox, $Anchor, $NoAuthCheck, $Select, $ReturnWithCommand, [switch]$Compliance, [switch]$AsApp) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecMailboxInventory.ps1')
    $script:Heuristics = Get-CIPPBecHeuristics
    $script:Upn = 'victim@contoso.com'

    # Build the cmdlet-keyed result New-ExoBulkRequest -ReturnWithCommand produces, stamping each row with its OperationGuid.
    function New-BulkResult {
        param([hashtable]$Rows)
        $Result = @{}
        foreach ($Guid in $Rows.Keys) {
            $Entry = $Rows[$Guid]
            $Cmdlet = $Entry.Cmdlet
            if (-not $Result.ContainsKey($Cmdlet)) { $Result[$Cmdlet] = [System.Collections.Generic.List[object]]::new() }
            foreach ($Row in @($Entry.Rows)) {
                $Row | Add-Member -NotePropertyName 'OperationGuid' -NotePropertyValue $Guid -Force
                $Result[$Cmdlet].Add($Row)
            }
        }
        $Result
    }
    function New-Round1 {
        param([switch]$OmitApps, [switch]$ErrorPermissions)
        $Rows = @{
            'Mailbox'             = @{ Cmdlet = 'Get-Mailbox'; Rows = @([pscustomobject]@{ PrimarySmtpAddress = $script:Upn; RecipientTypeDetails = 'UserMailbox'; ForwardingSmtpAddress = 'smtp:attacker@example.org'; ForwardingAddress = $null; DeliverToMailboxAndForward = $true; GrantSendOnBehalfTo = @('Assistant One', 'guest_example.org#EXT#@contoso.onmicrosoft.com'); AuditEnabled = $true }) }
            'CAS'                 = @{ Cmdlet = 'Get-CASMailbox'; Rows = @([pscustomobject]@{ OWAEnabled = $true; EWSEnabled = $true; IMAPEnabled = $false; POPEnabled = $false; MAPIEnabled = $true; ActiveSyncEnabled = $true; SmtpClientAuthenticationDisabled = $false; ActiveSyncBlockedDeviceIDs = @() }) }
            'AutoReply'           = @{ Cmdlet = 'Get-MailboxAutoReplyConfiguration'; Rows = @([pscustomobject]@{ AutoReplyState = 'Enabled'; StartTime = $null; EndTime = $null; ExternalAudience = 'All'; InternalMessage = 'SECRET INTERNAL TEXT'; ExternalMessage = 'SECRET EXTERNAL TEXT' }) }
            'MailboxPermission'   = @{ Cmdlet = 'Get-MailboxPermission'; Rows = @(
                    [pscustomobject]@{ User = 'NT AUTHORITY\SELF'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false }
                    [pscustomobject]@{ User = 'assistant@contoso.com'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false }
                    [pscustomobject]@{ User = 'outsider@example.org'; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false }
                    [pscustomobject]@{ User = 'inherited@contoso.com'; AccessRights = @('FullAccess'); IsInherited = $true; Deny = $false }
                    # the REST transport returns these as strings, and [bool]'False' is $true
                    [pscustomobject]@{ User = 'stringy@contoso.com'; AccessRights = @('FullAccess'); IsInherited = 'False'; Deny = 'False' }
                ) }
            'RecipientPermission' = @{ Cmdlet = 'Get-RecipientPermission'; Rows = @(
                    [pscustomobject]@{ Trustee = 'NT AUTHORITY\SELF'; AccessRights = @('SendAs'); IsInherited = $false; AccessControlType = 'Allow' }
                    [pscustomobject]@{ Trustee = 'assistant@contoso.com'; AccessRights = @('SendAs'); IsInherited = $false; AccessControlType = 'Allow' }
                ) }
            'FolderStats-Calendar' = @{ Cmdlet = 'Get-MailboxFolderStatistics'; Rows = @([pscustomobject]@{ FolderType = 'Calendar'; FolderId = 'LgAAAACalendar'; Name = 'Kalender' }, [pscustomobject]@{ FolderType = 'User Created'; FolderId = 'LgAAAASub'; Name = 'Sub' }) }
            'FolderStats-Inbox'   = @{ Cmdlet = 'Get-MailboxFolderStatistics'; Rows = @([pscustomobject]@{ FolderType = 'Inbox'; FolderId = 'LgAAAAInbox'; Name = 'Posteingang' }) }
        }
        if (-not $OmitApps) {
            $Rows['Apps'] = @{ Cmdlet = 'Get-App'; Rows = @(
                    [pscustomobject]@{ Identity = 'a1'; DisplayName = 'Contoso Connector'; AppId = 'a1'; Enabled = $true; ProviderName = 'Microsoft'; Scope = 'Organization'; Type = 'MarketPlace'; AppVersion = '1.0' }
                    [pscustomobject]@{ Identity = 'a2'; DisplayName = 'Mail Harvester'; AppId = 'a2'; Enabled = $true; ProviderName = 'Unknown Dev'; Scope = 'User'; Type = 'Private'; AppVersion = '0.1' }
                    [pscustomobject]@{ Identity = 'a3'; DisplayName = 'Disabled Thing'; AppId = 'a3'; Enabled = $false; ProviderName = 'Unknown Dev'; Scope = 'User'; Type = 'Private'; AppVersion = '0.1' }
                    [pscustomobject]@{ Identity = 'a4'; DisplayName = 'Stringly Disabled'; AppId = 'a4'; Enabled = 'False'; ProviderName = 'Unknown Dev'; Scope = 'User'; Type = 'Private'; AppVersion = '0.1' }
                ) }
        }
        if ($ErrorPermissions) {
            $Rows['MailboxPermission'] = @{ Cmdlet = 'Get-MailboxPermission'; Rows = @([pscustomobject]@{ error = 'The operation could not be performed because object could not be found'; target = $script:Upn }) }
        }
        New-BulkResult -Rows $Rows
    }
    function New-Round2 {
        New-BulkResult -Rows @{
            'FolderPermission-Calendar' = @{ Cmdlet = 'Get-MailboxFolderPermission'; Rows = @(
                    [pscustomobject]@{ User = [pscustomobject]@{ DisplayName = 'Default' }; AccessRights = @('AvailabilityOnly') }
                    [pscustomobject]@{ User = [pscustomobject]@{ DisplayName = 'Anonymous' }; AccessRights = @('None') }
                    [pscustomobject]@{ User = [pscustomobject]@{ DisplayName = 'Assistant One'; ADRecipient = [pscustomobject]@{ PrimarySmtpAddress = 'assistant@contoso.com' } }; AccessRights = @('Editor') }
                ) }
            'FolderPermission-Inbox'    = @{ Cmdlet = 'Get-MailboxFolderPermission'; Rows = @(
                    [pscustomobject]@{ User = [pscustomobject]@{ DisplayName = 'Default' }; AccessRights = @('Reviewer') }
                ) }
        }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Get-CIPPBecMailboxInventory' {
    It 'builds the delegation inventory across the five types and flags external, guest and catch-all trustees' {
        $script:Round = 0
        Mock New-ExoBulkRequest { $script:Round++; if ($script:Round -eq 1) { New-Round1 } else { New-Round2 } }
        $Result = Get-CIPPBecMailboxInventory -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com', 'contoso.onmicrosoft.com')
        $Result.Delegations.Complete | Should -BeTrue
        $D = $Result.Delegations.Data
        ($D | Where-Object { $_.PermissionType -eq 'FullAccess' }).Trustee | Should -Not -Contain 'NT AUTHORITY\SELF'
        ($D | Where-Object { $_.PermissionType -eq 'FullAccess' }).Trustee | Should -Not -Contain 'inherited@contoso.com'
        ($D | Where-Object { $_.PermissionType -eq 'FullAccess' -and $_.Trustee -eq 'assistant@contoso.com' }).Flagged | Should -BeFalse
        ($D | Where-Object { $_.PermissionType -eq 'FullAccess' -and $_.Trustee -eq 'outsider@example.org' }).Flagged | Should -BeTrue
        $Stringy = $D | Where-Object { $_.PermissionType -eq 'FullAccess' -and $_.Trustee -eq 'stringy@contoso.com' }
        $Stringy | Should -Not -BeNullOrEmpty -Because 'IsInherited "False" (a string) is not inherited'
        $Stringy.Deny | Should -BeFalse -Because 'Deny "False" (a string) is an allow entry'
        ($D | Where-Object { $_.PermissionType -eq 'FullAccess' -and $_.Trustee -eq 'assistant@contoso.com' }).Deny | Should -BeFalse
        ($D | Where-Object { $_.PermissionType -eq 'SendAs' }).Trustee | Should -Be 'assistant@contoso.com'
        ($D | Where-Object { $_.PermissionType -eq 'SendOnBehalf' -and $_.Trustee -like '*#EXT#*' }).Flagged | Should -BeTrue
        ($D | Where-Object { $_.PermissionType -eq 'SendOnBehalf' -and $_.Trustee -eq 'Assistant One' }).Flagged | Should -BeFalse
        $Folders = @($D | Where-Object { $_.PermissionType -eq 'Folder' })
        $Folders.Trustee | Should -Not -Contain 'Anonymous'
        ($Folders | Where-Object { $_.Resource -like '*Calendar' }).Trustee | Should -Not -Contain 'Default' -Because 'AvailabilityOnly for Default is the normal calendar default'
        ($Folders | Where-Object { $_.Resource -like '*Inbox' -and $_.Trustee -eq 'Default' }).Flagged | Should -BeTrue -Because 'Reviewer on the Inbox for everyone is exposure'
        ($Folders | Where-Object { $_.Trustee -eq 'Assistant One' }).AccessRights | Should -Be 'Editor'
        $D[0].Flagged | Should -BeTrue -Because 'flagged delegations sort first'
    }

    It 'reads folder permissions by folder id, not by localised folder name' {
        $script:Round = 0
        $script:Round2Array = $null
        Mock New-ExoBulkRequest { $script:Round++; if ($script:Round -eq 1) { New-Round1 } else { $script:Round2Array = $cmdletArray; New-Round2 } }
        $null = Get-CIPPBecMailboxInventory -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Identities = @($script:Round2Array | ForEach-Object { $_.CmdletInput.Parameters.Identity })
        $Identities | Should -Contain "$($script:Upn):LgAAAACalendar"
        $Identities | Should -Contain "$($script:Upn):LgAAAAInbox"
        $Identities | Should -Not -Contain "$($script:Upn):LgAAAASub"
        $Identities -join ' ' | Should -Not -Match 'Kalender|Posteingang'
    }

    It 'captures forwarding, auto-reply state and protocols without the auto-reply text' {
        $script:Round = 0
        Mock New-ExoBulkRequest { $script:Round++; if ($script:Round -eq 1) { New-Round1 } else { New-Round2 } }
        $Result = Get-CIPPBecMailboxInventory -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $State = $Result.MailboxState.Data
        $Result.MailboxState.Complete | Should -BeTrue
        $State.HasForwarding | Should -BeTrue
        $State.ForwardingSmtpAddress | Should -Be 'smtp:attacker@example.org'
        $State.DeliverToMailboxAndForward | Should -BeTrue
        $State.AutoReplyState | Should -Be 'Enabled'
        $State.AutoReplyHasInternalMessage | Should -BeTrue
        $State.IMAPEnabled | Should -BeFalse
        $State.EWSEnabled | Should -BeTrue
        ($State | ConvertTo-Json -Depth 5) | Should -Not -Match 'SECRET'
    }

    It 'flags enabled, user-installed, non-Microsoft add-ins only' {
        $script:Round = 0
        Mock New-ExoBulkRequest { $script:Round++; if ($script:Round -eq 1) { New-Round1 } else { New-Round2 } }
        $Result = Get-CIPPBecMailboxInventory -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Result.AddIns.Complete | Should -BeTrue
        $Result.AddIns.Data.Count | Should -Be 4
        ($Result.AddIns.Data | Where-Object { $_.DisplayName -eq 'Mail Harvester' }).Flagged | Should -BeTrue
        $Stringly = $Result.AddIns.Data | Where-Object { $_.DisplayName -eq 'Stringly Disabled' }
        $Stringly.Enabled | Should -BeFalse -Because 'Enabled "False" (a string) is disabled'
        $Stringly.Flagged | Should -BeFalse
        ($Result.AddIns.Data | Where-Object { $_.DisplayName -eq 'Contoso Connector' }).Flagged | Should -BeFalse
        ($Result.AddIns.Data | Where-Object { $_.DisplayName -eq 'Disabled Thing' }).Flagged | Should -BeFalse
    }

    It 'reports a missing sub-request as incomplete instead of an empty list' {
        $script:Round = 0
        Mock New-ExoBulkRequest { $script:Round++; if ($script:Round -eq 1) { New-Round1 -OmitApps } else { New-Round2 } }
        $Result = Get-CIPPBecMailboxInventory -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Result.AddIns.Complete | Should -BeFalse
        $Result.AddIns.Error | Should -Match 'Get-App returned no response'
        $Result.Delegations.Complete | Should -BeTrue
    }

    It 'reports an errored sub-request as incomplete with the error text' {
        $script:Round = 0
        Mock New-ExoBulkRequest { $script:Round++; if ($script:Round -eq 1) { New-Round1 -ErrorPermissions } else { New-Round2 } }
        $Result = Get-CIPPBecMailboxInventory -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Result.Delegations.Complete | Should -BeFalse
        $Result.Delegations.Error | Should -Match 'could not be found'
        ($Result.Delegations.Data | Where-Object { $_.PermissionType -eq 'SendAs' }).Count | Should -Be 1 -Because 'the other permission types still load'
        $Result.MailboxState.Complete | Should -BeTrue
    }

    It 'treats a swallowed transport failure (empty bulk result) as everything incomplete' {
        Mock New-ExoBulkRequest { @{} }
        $Result = Get-CIPPBecMailboxInventory -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -Heuristics $script:Heuristics -AcceptedDomains @('contoso.com')
        $Result.MailboxState.Complete | Should -BeFalse
        $Result.Delegations.Complete | Should -BeFalse
        $Result.AddIns.Complete | Should -BeFalse
        $Result.Delegations.Data.Count | Should -Be 0
    }
}
