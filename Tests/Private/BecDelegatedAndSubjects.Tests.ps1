BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) }
    function Get-CIPPMailboxPermissionReport { param($TenantFilter, [switch]$ByUser) }
    function Get-CIPPCalendarPermissionReport { param($TenantFilter, [switch]$ByUser) }
    function Get-NormalizedError { param($message) $message }
    foreach ($File in @('BEC/New-CIPPBecCollectorResult.ps1', 'BEC/Resolve-CIPPBecMessageSubjects.ps1', 'BEC/Get-CIPPBecDelegatedAccess.ps1')) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
}

Describe 'Resolve-CIPPBecMessageSubjects' {
    It 'uses the known subjects first, then traces the rest newest slice first, and stops once all are named' {
        $script:Slices = [System.Collections.Generic.List[object]]::new()
        Mock New-ExoRequest {
            $script:Slices.Add($cmdParams)
            if ($script:Slices.Count -eq 2) { @([pscustomobject]@{ MessageId = '<b@x>'; Subject = 'Wire details' }, [pscustomobject]@{ MessageId = '<c@x>'; Subject = 'Payroll' }) }
        }
        $Result = Resolve-CIPPBecMessageSubjects -TenantFilter 'contoso.com' -MessageIds @('<a@x>', '<b@x>', '<c@x>', '<b@x>') -Known @{ '<a@x>' = 'Invoice' }
        $Result.Subjects['<a@x>'] | Should -Be 'Invoice'
        $Result.Subjects['<c@x>'] | Should -Be 'Payroll'
        $Result.Unresolved | Should -Be 0
        $script:Slices.Count | Should -Be 2 -Because 'the walk stops as soon as every id is named'
        $script:Slices[0].MessageId.GetType().IsArray | Should -BeTrue -Because 'a joined string silently matches nothing'
        @($script:Slices[0].MessageId).Count | Should -Be 2
        ([datetime]$script:Slices[1].EndDate) | Should -Be ([datetime]$script:Slices[0].StartDate)
    }

    It 'walks at most the lookback in 10-day slices and leaves older messages unnamed' {
        $script:Slices = [System.Collections.Generic.List[object]]::new()
        Mock New-ExoRequest { $script:Slices.Add($cmdParams) }
        $Result = Resolve-CIPPBecMessageSubjects -TenantFilter 'contoso.com' -MessageIds @('<old@x>') -LookbackDays 30
        $script:Slices.Count | Should -Be 3
        $Result.Unresolved | Should -Be 1
    }

    It 'reports a failed trace and stops' {
        Mock New-ExoRequest { throw 'Get-MessageTraceV2 throttled' }
        $Result = Resolve-CIPPBecMessageSubjects -TenantFilter 'contoso.com' -MessageIds @('<a@x>')
        $Result.Error | Should -Match 'throttled'
        Should -Invoke New-ExoRequest -Times 1
    }
}

Describe 'Get-CIPPBecDelegatedAccess' {
    It 'joins the permission cache, window grants and delegate activity, and marks what the attacker did in each mailbox' {
        Mock Get-CIPPMailboxPermissionReport { @(
                [pscustomobject]@{ User = 'Victim@contoso.com'; Permissions = @([pscustomobject]@{ Mailbox = 'CEO'; MailboxUPN = 'ceo@contoso.com'; AccessRights = 'FullAccess, SendAs' }) }
                [pscustomobject]@{ User = 'other@contoso.com'; Permissions = @([pscustomobject]@{ MailboxUPN = 'hr@contoso.com'; AccessRights = 'FullAccess' }) }
            ) }
        Mock Get-CIPPCalendarPermissionReport { @([pscustomobject]@{ User = 'Victim Person'; Permissions = @([pscustomobject]@{ CalendarUPN = 'cfo@contoso.com'; AccessRights = 'Editor' }) }) }
        $Changes = @([pscustomobject]@{ Operation = 'Add-MailboxPermission'; Trustee = 'victim@contoso.com'; ObjectId = 'finance@contoso.com'; Permissions = 'FullAccess'; AuditData = $null })
        $Activity = @([pscustomobject]@{ Operation = 'MailItemsAccessed'; MailboxOwner = 'ceo@contoso.com'; Count = 30 }, [pscustomobject]@{ Operation = 'MailItemsAccessed'; MailboxOwner = 'victim@contoso.com'; Count = 900 })
        $Attacker = @(
            [pscustomobject]@{ Operation = 'MailItemsAccessed'; AccessType = 'Bind'; MailboxOwner = 'ceo@contoso.com'; When = '2026-09-20T01:00:00Z' }
            [pscustomobject]@{ Operation = 'SendAs'; MailboxOwner = 'ceo@contoso.com'; When = '2026-09-20T02:00:00Z' }
        )
        $Result = Get-CIPPBecDelegatedAccess -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -UserDisplayName 'Victim Person' -PermissionChanges $Changes -MailActivity $Activity -AttackerMail $Attacker
        $Result.Complete | Should -BeTrue
        @($Result.Data.Mailbox) | Should -Not -Contain 'hr@contoso.com'
        @($Result.Data.Mailbox) | Should -Not -Contain 'victim@contoso.com'
        $Ceo = $Result.Data | Where-Object Mailbox -EQ 'ceo@contoso.com'
        $Ceo.AccessRights | Should -Be 'FullAccess, SendAs'
        $Ceo.KnownFrom | Should -Be 'Delegate activity, Permission cache'
        $Ceo.DelegateActivity | Should -Be 30
        $Ceo.AttackerOpened | Should -Be 1
        $Ceo.AttackerSent | Should -Be 1
        $Ceo.LastAttackerActivity | Should -Be '2026-09-20T02:00:00Z'
        $Result.Data[0].Mailbox | Should -Be 'ceo@contoso.com' -Because 'mailboxes the attacker used sort first'
        ($Result.Data | Where-Object Mailbox -EQ 'finance@contoso.com').GrantedInWindow | Should -BeTrue
        ($Result.Data | Where-Object Mailbox -EQ 'cfo@contoso.com').AccessRights | Should -Be 'Calendar: Editor' -Because 'calendar delegates are often named by display name'
    }

    It 'still reports the audit and activity sources when the permission cache has not been built' {
        Mock Get-CIPPMailboxPermissionReport { throw 'No mailbox data found in reporting database. Sync the mailbox permissions first.' }
        Mock Get-CIPPCalendarPermissionReport { @() }
        $Result = Get-CIPPBecDelegatedAccess -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -MailActivity @([pscustomobject]@{ MailboxOwner = 'ceo@contoso.com'; Count = 3 })
        $Result.Complete | Should -BeFalse
        $Result.Error | Should -Match 'Sync the mailbox permissions first'
        $Result.Data[0].Mailbox | Should -Be 'ceo@contoso.com'
    }
}
