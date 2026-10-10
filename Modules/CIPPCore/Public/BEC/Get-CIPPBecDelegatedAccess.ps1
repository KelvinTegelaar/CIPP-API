function Get-CIPPBecDelegatedAccess {
    <#
    .SYNOPSIS
        Lists the other mailboxes the investigated account can reach, and what the attacker did in them.
    .DESCRIPTION
        A compromised account reaches every mailbox it has delegate access to. The mailboxes come from:
        - CIPP's permission cache (the reverse lookup of the mailbox and calendar permission reports,
          Get-CIPPMailboxPermissionReport / Get-CIPPCalendarPermissionReport -ByUser), which may be
          a few hours old;
        - grants to this account recorded in the window's audit log (Add-MailboxPermission,
          Add-RecipientPermission, folder grants), which catch a fresh or already-removed grant;
        - mailbox activity by this account in a mailbox it does not own (MailItemsAccessed and sends
          logged as a delegate), which catches access neither of the above knows about.
        Each mailbox row carries its access rights and where they are known from, the delegate
        activity counted in it, and the item-level attacker activity (opened, synced, sent) in it.
        A permission cache that has not been built is reported as an error while the audit and
        activity sources still count.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The investigated user.
    .PARAMETER UserDisplayName
        The user's display name (calendar permissions often name the delegate that way).
    .PARAMETER PermissionChanges
        The window's mailbox permission changes (MailboxPermissionChanges).
    .PARAMETER MailActivity
        The mailbox activity counts (MailActivity rows).
    .PARAMETER AttackerMail
        The attacker-side mail rows (Get-CIPPBecAttackerActivity Mail data).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [string]$UserDisplayName,
        [object[]]$PermissionChanges = @(),
        [object[]]$MailActivity = @(),
        [object[]]$AttackerMail = @()
    )

    $IsUser = { param($Value) $Text = ([string]$Value).Trim(); $Text -and ($Text -ieq $UserPrincipalName -or ($UserDisplayName -and $Text -ieq $UserDisplayName)) }
    $Mailboxes = @{}
    $Touch = {
        param($Mailbox)
        $Key = ([string]$Mailbox).Trim().ToLowerInvariant()
        if (-not $Mailboxes.ContainsKey($Key)) {
            $Mailboxes[$Key] = [pscustomobject]@{
                Mailbox = [string]$Mailbox; AccessRights = [System.Collections.Generic.HashSet[string]]::new(); Sources = [System.Collections.Generic.HashSet[string]]::new()
                GrantedInWindow = $false; DelegateActivity = 0; AttackerOpened = 0; AttackerSynced = 0; AttackerSent = 0; LastAttackerActivity = $null
            }
        }
        $Mailboxes[$Key]
    }
    $Errors = [System.Collections.Generic.List[string]]::new()

    try {
        foreach ($Entry in @(Get-CIPPMailboxPermissionReport -TenantFilter $TenantFilter -ByUser | Where-Object { & $IsUser $_.User })) {
            foreach ($Permission in @($Entry.Permissions)) {
                $Target = if ($Permission.MailboxUPN) { $Permission.MailboxUPN } else { $Permission.Mailbox }
                if (& $IsUser $Target) { continue }
                $Row = & $Touch $Target
                foreach ($Right in @(([string]$Permission.AccessRights) -split ',\s*' | Where-Object { $_ })) { $null = $Row.AccessRights.Add($Right) }
                $null = $Row.Sources.Add('Permission cache')
            }
        }
    } catch {
        $Errors.Add("mailbox permission cache: $($_.Exception.Message)")
    }
    try {
        foreach ($Entry in @(Get-CIPPCalendarPermissionReport -TenantFilter $TenantFilter -ByUser | Where-Object { & $IsUser $_.User })) {
            foreach ($Permission in @($Entry.Permissions)) {
                if (& $IsUser $Permission.CalendarUPN) { continue }
                $Row = & $Touch $Permission.CalendarUPN
                $null = $Row.AccessRights.Add("Calendar: $($Permission.AccessRights)")
                $null = $Row.Sources.Add('Permission cache')
            }
        }
    } catch {
        $Errors.Add("calendar permission cache: $($_.Exception.Message)")
    }

    foreach ($Change in @($PermissionChanges | Where-Object { $_ -and (& $IsUser $_.Trustee) -and [string]$_.Operation -match '^(Add-|Update|AddFolder)' })) {
        $Target = if ($Change.AuditData.MailboxOwnerUPN) { $Change.AuditData.MailboxOwnerUPN } else { $Change.ObjectId }
        if (-not $Target -or (& $IsUser $Target)) { continue }
        $Row = & $Touch $Target
        foreach ($Right in @(@($Change.Permissions) -split ',\s*' | Where-Object { $_ })) { $null = $Row.AccessRights.Add([string]$Right) }
        $null = $Row.Sources.Add('Granted in the window')
        $Row.GrantedInWindow = $true
    }

    foreach ($Activity in @($MailActivity | Where-Object { $_ -and $_.MailboxOwner -and -not (& $IsUser $_.MailboxOwner) })) {
        $Row = & $Touch $Activity.MailboxOwner
        $Row.DelegateActivity = $Row.DelegateActivity + [int]$Activity.Count
        $null = $Row.Sources.Add('Delegate activity')
    }
    foreach ($Item in @($AttackerMail | Where-Object { $_ -and $_.MailboxOwner -and -not (& $IsUser $_.MailboxOwner) })) {
        $Row = & $Touch $Item.MailboxOwner
        if ($Item.Operation -eq 'MailItemsAccessed' -and $Item.AccessType -eq 'Sync') { $Row.AttackerSynced++ }
        elseif ($Item.Operation -eq 'MailItemsAccessed') { $Row.AttackerOpened++ }
        elseif ($Item.Operation -in @('Send', 'SendAs', 'SendOnBehalf')) { $Row.AttackerSent++ }
        if ($Item.When -and (-not $Row.LastAttackerActivity -or [string]$Item.When -gt $Row.LastAttackerActivity)) { $Row.LastAttackerActivity = [string]$Item.When }
    }

    $Rows = @($Mailboxes.Values | ForEach-Object {
            [pscustomobject]@{
                Mailbox              = $_.Mailbox
                AccessRights         = @($_.AccessRights | Sort-Object) -join ', '
                KnownFrom            = @($_.Sources | Sort-Object) -join ', '
                GrantedInWindow      = $_.GrantedInWindow
                DelegateActivity     = $_.DelegateActivity
                AttackerOpened       = $_.AttackerOpened
                AttackerSynced       = $_.AttackerSynced
                AttackerSent         = $_.AttackerSent
                LastAttackerActivity = $_.LastAttackerActivity
                Flagged              = [bool]($_.AttackerOpened + $_.AttackerSynced + $_.AttackerSent -gt 0 -or $_.GrantedInWindow)
            }
        } | Sort-Object -Property @{ Expression = { $_.Flagged }; Descending = $true }, @{ Expression = { $_.AttackerOpened + $_.AttackerSynced + $_.AttackerSent }; Descending = $true }, Mailbox)
    New-CIPPBecCollectorResult -Data $Rows -Error $(if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null })
}
