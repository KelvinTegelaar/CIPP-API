BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Search-CIPPBecAuditLog { param($TenantFilter, $StartDate, $EndDate, $Operations, $UserIds, $RecordType, $ObjectIds, $IPAddresses, $FreeText, $Anchor, $MaxPages) }
    function Resolve-CIPPBecMessageSubjects { param($TenantFilter, $MessageIds, $Known, $LookbackDays, $Anchor) }
    function Get-NormalizedError { param($message) $message }
    foreach ($File in @('BEC/ConvertTo-CIPPBecHostAddress.ps1', 'BEC/New-CIPPBecCollectorResult.ps1', 'BEC/Get-CIPPBecAttackerActivity.ps1')) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
    $script:Heuristics = Get-Content (Join-Path $RepoRoot 'Config/BecHeuristics.json') -Raw | ConvertFrom-Json
    $script:Verdicts = @(
        [pscustomobject]@{ IP = '198.51.100.7'; Verdict = 'LikelyAttacker' }
        [pscustomobject]@{ IP = '192.0.2.44'; Verdict = 'Unknown' }
        [pscustomobject]@{ IP = '203.0.113.10'; Verdict = 'LikelyUser' }
        [pscustomobject]@{ IP = '40.107.1.1'; Verdict = 'Service' }
    )
    $script:SignIns = @([pscustomobject]@{ IPAddress = '198.51.100.7'; UniqueTokenId = 'TOK-ATTACKER'; SessionId = 'ENTRA-1' })
    function New-Mail {
        param($Operation, $IP, [hashtable]$Extra = @{})
        $AD = [ordered]@{ Operation = $Operation; CreationTime = '2026-09-20T01:00:00Z'; UserId = 'victim@contoso.com'; MailboxOwnerUPN = 'victim@contoso.com'; LogonType = 0; ClientInfoString = 'Client=OWA' }
        if ($IP) { $AD.ClientIPAddress = $IP }
        foreach ($Key in $Extra.Keys) { $AD[$Key] = $Extra[$Key] }
        [pscustomobject]@{ Operation = $Operation; AuditData = [pscustomobject]$AD }
    }
    function Invoke-Attacker {
        param($MailRecords = @(), $SharingChanges = @())
        Get-CIPPBecAttackerActivity -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate '2026-09-16' -EndDate '2026-09-23' -Heuristics $script:Heuristics -Verdicts $script:Verdicts -SignIns $script:SignIns -MailRecords $MailRecords -SharingChanges $SharingChanges -KnownSubjects @{ '<known@x>' = 'Invoice 443' } -Anchor 'victim@contoso.com'
    }
}

Describe 'Get-CIPPBecAttackerActivity' {
    BeforeEach {
        Mock Search-CIPPBecAuditLog { [pscustomobject]@{ Records = @(); Complete = $true; Cap = $null } }
        Mock Resolve-CIPPBecMessageSubjects { [pscustomobject]@{ Subjects = @{ '<known@x>' = 'Invoice 443'; '<traced@x>' = 'Wire details' }; Resolved = 2; Unresolved = 1; Error = $null } }
    }

    It 'details the attacker side item by item and leaves the user side as counts' {
        $Bind = New-Mail 'MailItemsAccessed' '198.51.100.7:51234' @{ OperationProperties = @([pscustomobject]@{ Name = 'MailAccessType'; Value = 'Bind' }); Folders = @([pscustomobject]@{ Path = '\Inbox'; FolderItems = @([pscustomobject]@{ InternetMessageId = '<known@x>' }, [pscustomobject]@{ InternetMessageId = '<traced@x>' }, [pscustomobject]@{ InternetMessageId = '<old@x>' }) }) }
        $Sync = New-Mail 'MailItemsAccessed' '192.0.2.44' @{ OperationProperties = @([pscustomobject]@{ Name = 'MailAccessType'; Value = 'Sync' }); Folders = @([pscustomobject]@{ Path = '\Sent Items'; FolderItems = @(1..40 | ForEach-Object { [pscustomobject]@{ InternetMessageId = "<s$_@x>" } }) }) }
        $Delete = New-Mail 'SoftDelete' '198.51.100.7' @{ AffectedItems = @([pscustomobject]@{ Subject = 'Security alert'; InternetMessageId = '<d1@x>'; ParentFolder = [pscustomobject]@{ Path = '\Inbox' } }) }
        $Move = New-Mail 'Move' '198.51.100.7' @{ DestFolder = [pscustomobject]@{ Path = '\RSS Feeds' }; AffectedItems = @([pscustomobject]@{ Subject = 'RE: payment'; ParentFolder = [pscustomobject]@{ Path = '\Inbox' } }) }
        $Send = New-Mail 'Send' '198.51.100.7' @{ Item = [pscustomobject]@{ Subject = 'Updated bank details'; InternetMessageId = '<sent@x>'; ParentFolder = [pscustomobject]@{ Path = '\Sent Items' } } }
        $UserSide = New-Mail 'MailItemsAccessed' '203.0.113.10' @{ Folders = @([pscustomobject]@{ Path = '\Inbox'; FolderItems = @([pscustomobject]@{ InternetMessageId = '<mine@x>' }) }) }
        $Result = Invoke-Attacker -MailRecords @($Bind, $Sync, $Delete, $Move, $Send, $UserSide)
        $Rows = @($Result.Mail.Data)
        @($Rows | Where-Object InternetMessageId -EQ '<mine@x>').Count | Should -Be 0 -Because "the user's own reads stay counts"
        ($Rows | Where-Object InternetMessageId -EQ '<known@x>').Subject | Should -Be 'Invoice 443'
        ($Rows | Where-Object InternetMessageId -EQ '<traced@x>').Subject | Should -Be 'Wire details'
        ($Rows | Where-Object InternetMessageId -EQ '<old@x>').Subject | Should -BeNullOrEmpty -Because 'older than the trace keeps its id only'
        $Synced = $Rows | Where-Object AccessType -EQ 'Sync'
        $Synced.ItemCount | Should -Be 40
        $Synced.IPVerdict | Should -Be 'Unknown'
        ($Rows | Where-Object Operation -EQ 'Move').Detail | Should -Be 'to \RSS Feeds'
        ($Rows | Where-Object Operation -EQ 'SoftDelete').Subject | Should -Be 'Security alert'
        ($Rows | Where-Object Operation -EQ 'Send').Subject | Should -Be 'Updated bank details'
        $Result.Mail.Summary.MessagesOpened | Should -Be 3
        $Result.Mail.Summary.FoldersSynced | Should -Be 1
        $Result.Mail.Summary.Deleted | Should -Be 1
        $Result.Mail.Summary.Sent | Should -Be 1
        Should -Invoke Resolve-CIPPBecMessageSubjects -Times 1 -ParameterFilter { @($MessageIds).Count -eq 3 -and $Known['<known@x>'] -eq 'Invoice 443' }
    }

    It 'lands a record without an address, or on a Microsoft front end, on the sign-in behind its token or session' {
        $NoIP = New-Mail 'MailItemsAccessed' $null @{ AppAccessContext = [pscustomobject]@{ UniqueTokenId = 'TOK-ATTACKER' }; Folders = @([pscustomobject]@{ Path = '\Inbox'; FolderItems = @([pscustomobject]@{ InternetMessageId = '<a@x>' }) }) }
        $FrontEnd = New-Mail 'MailItemsAccessed' '40.107.1.1' @{ AppAccessContext = [pscustomobject]@{ AADSessionId = 'ENTRA-1' }; Folders = @([pscustomobject]@{ Path = '\Inbox'; FolderItems = @([pscustomobject]@{ InternetMessageId = '<b@x>' }) }) }
        $Orphan = New-Mail 'MailItemsAccessed' $null @{ Folders = @([pscustomobject]@{ Path = '\Inbox'; FolderItems = @([pscustomobject]@{ InternetMessageId = '<c@x>' }) }) }
        $Result = Invoke-Attacker -MailRecords @($NoIP, $FrontEnd, $Orphan)
        $A = $Result.Mail.Data | Where-Object InternetMessageId -EQ '<a@x>'
        $A.IP | Should -Be '198.51.100.7'
        $A.IPSource | Should -Be 'token'
        ($Result.Mail.Data | Where-Object InternetMessageId -EQ '<b@x>').IPSource | Should -Be 'Entra session'
        $Result.Mail.Summary.Unattributed | Should -Be 1 -Because 'a record tied to nothing is counted, not guessed'
    }

    It 'searches files only for the attacker-side addresses and link usage by item' {
        Mock Search-CIPPBecAuditLog -ParameterFilter { $IPAddresses } {
            [pscustomobject]@{ Complete = $true; Records = @([pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'FileDownloaded'; CreationTime = '2026-09-20T02:00:00Z'; SourceFileName = 'payroll.xlsx'; ObjectId = 'https://contoso-my.sharepoint.com/personal/victim/Documents/payroll.xlsx'; SiteUrl = 'https://contoso-my.sharepoint.com/personal/victim'; ClientIP = '198.51.100.7'; UserAgent = 'python-requests/2.31' } }) }
        }
        Mock Search-CIPPBecAuditLog -ParameterFilter { $ObjectIds } {
            [pscustomobject]@{ Complete = $true; Records = @([pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'AnonymousLinkUsed'; CreationTime = '2026-09-21T02:00:00Z'; SourceFileName = 'invoice.pdf'; ObjectId = 'https://contoso-my.sharepoint.com/personal/victim/Documents/invoice.pdf'; UserId = 'urn:spo:anon#1'; ClientIP = '203.0.113.200' } }) }
        }
        $Result = Invoke-Attacker -SharingChanges @([pscustomobject]@{ ItemUrl = 'https://contoso-my.sharepoint.com/personal/victim/Documents/invoice.pdf'; Operation = 'AnonymousLinkCreated' })
        Should -Invoke Search-CIPPBecAuditLog -Times 1 -ParameterFilter { $IPAddresses -and @($IPAddresses | Sort-Object) -join ',' -eq '192.0.2.44,198.51.100.7' -and $Operations -contains 'FileDownloaded' -and $UserIds -contains 'victim@contoso.com' }
        $Result.Files.Data[0].File | Should -Be 'payroll.xlsx'
        $Result.Files.Data[0].IPVerdict | Should -Be 'LikelyAttacker'
        $Result.Files.Summary.Downloaded | Should -Be 1
        $Result.LinkUsage.Data[0].OpenedBy | Should -Be 'urn:spo:anon#1'
        Should -Invoke Search-CIPPBecAuditLog -Times 1 -ParameterFilter { $ObjectIds -contains 'https://contoso-my.sharepoint.com/personal/victim/Documents/invoice.pdf' -and $Operations -contains 'AnonymousLinkUsed' }
    }

    It 'flags Forms built from an attacker address and counts who answered them' {
        Mock Search-CIPPBecAuditLog -ParameterFilter { $RecordType -eq 'MicrosoftForms' } {
            [pscustomobject]@{ Complete = $true; Records = @(
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'CreateForm'; CreationTime = '2026-09-20T03:00:00Z'; FormId = 'FORM1'; FormName = 'Microsoft 365 password check'; FormsUserType = 'Owner'; ClientIP = '198.51.100.7' } }
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'CreateForm'; CreationTime = '2026-09-19T03:00:00Z'; FormId = 'FORM2'; FormName = 'Team lunch'; FormsUserType = 'Owner'; ClientIP = '203.0.113.10' } }
                ) }
        }
        Mock Search-CIPPBecAuditLog -ParameterFilter { $FreeText -eq 'FORM1' } {
            [pscustomobject]@{ Complete = $true; Records = @(
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'SubmitResponse'; FormId = 'FORM1'; ResponderId = 'r1' } }
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'SubmitResponse'; FormId = 'FORM1'; ResponderId = $null } }
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'ViewRuntimeForm'; FormId = 'FORM1' } }
                    [pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'UpdatePhishingStatus'; FormId = 'FORM1' } }
                ) }
        }
        $Result = Invoke-Attacker
        ($Result.Forms.Data | Where-Object FormId -EQ 'FORM1').Flagged | Should -BeTrue
        ($Result.Forms.Data | Where-Object FormId -EQ 'FORM2').Flagged | Should -BeFalse
        $Reach = $Result.Forms.Summary.Forms | Where-Object FormId -EQ 'FORM1'
        $Reach.Responses | Should -Be 2
        $Reach.AnonymousResponses | Should -Be 1
        $Reach.Views | Should -Be 1
        $Reach.PhishingFlagged | Should -BeTrue
        Should -Invoke Search-CIPPBecAuditLog -Times 0 -ParameterFilter { $FreeText -eq 'FORM2' }
    }

    It 'reports a failed search as an error on that section only' {
        Mock Search-CIPPBecAuditLog -ParameterFilter { $IPAddresses } { throw 'Search-UnifiedAuditLog timed out' }
        $Result = Invoke-Attacker
        $Result.Files.Error | Should -Match 'timed out'
        $Result.Mail.Complete | Should -BeTrue
        $Result.Forms.Complete | Should -BeTrue
    }
}
