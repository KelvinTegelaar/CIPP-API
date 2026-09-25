function ConvertTo-CIPPBecIPEvents {
    <#
    .SYNOPSIS
        Flattens a BEC results payload into the per-address activity the IP verdicts are built from.
    .DESCRIPTION
        One { IP, Kind, Flagged, ActorKind, When, SessionIds } per audited action the investigated
        account took. Tenant-wide sections (mailbox permission changes, transport rule changes,
        directory audits) only contribute the rows this account made - another admin's address says
        nothing about who holds this account. Flagged marks the actions an attacker takes: a suspicious
        inbox rule, a permission change on this mailbox, a safelist change, an anonymous link, a risky
        transport rule change, a flagged directory event (security info, consent, device), or mail
        sent as part of a mass-mail pattern.
    .PARAMETER Results
        The BEC results payload (as assembled by Push-BECRun or read back from storage).
    .PARAMETER UserPrincipalName
        The investigated user.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Results,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName
    )

    $IsUser = { param($Value) [string]$Value -and ([string]$Value).Trim() -ieq $UserPrincipalName }
    $Leaf = { param($Value) (([string]$Value) -split '\\')[-1] }
    $SuspiciousRules = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Rule in @($Results.NewRules | Where-Object { $_ -and $_.Suspicious -eq $true })) { $null = $SuspiciousRules.Add([string]$Rule.Name) }
    $MassMail = $Results.SentMessageAnalysis.Flagged -eq $true
    $New = { param($IP, $Kind, $Flagged, $ActorKind, $When, $SessionIds) [pscustomobject]@{ IP = $IP; Kind = $Kind; Flagged = [bool]$Flagged; ActorKind = $(if ($ActorKind) { [string]$ActorKind } else { 'User' }); When = $When; SessionIds = @($SessionIds | Where-Object { $_ }) } }

    @(
        foreach ($Row in @($Results.InboxRuleChanges | Where-Object { $_.ClientIP })) {
            & $New $Row.ClientIP 'Inbox rule change' ($SuspiciousRules.Contains((& $Leaf $Row.RuleName))) $Row.ActorKind $Row.Date
        }
        foreach ($Row in @($Results.MailboxPermissionChanges | Where-Object { $_.ClientIP -and ((& $IsUser $_.UserId) -or (& $IsUser $_.UserKey)) })) {
            & $New $Row.ClientIP 'Mailbox permission change' $Row.TargetsSuspect $Row.ActorKind $Row.Date
        }
        foreach ($Row in @($Results.SafelistChanges | Where-Object { $_.ClientIP })) {
            & $New $Row.ClientIP 'Safelist change' $true $Row.ActorKind $Row.Date
        }
        foreach ($Row in @($Results.SharingChanges | Where-Object { $_.ClientIP })) {
            & $New $Row.ClientIP 'Sharing change' ([string]$Row.Operation -like 'AnonymousLink*') $Row.ActorKind $Row.Date
        }
        foreach ($Row in @($Results.TransportRuleChanges | Where-Object { $_.ClientIP -and (& $IsUser $_.Actor) })) {
            & $New $Row.ClientIP 'Transport rule change' ($Row.Flagged -eq $true) $Row.ActorKind $Row.Date
        }
        foreach ($Row in @($Results.DirectoryAudits | Where-Object { $_.ClientIP -and (& $IsUser $_.InitiatedBy) })) {
            & $New $Row.ClientIP 'Directory change' ($Row.Flagged -eq $true) $Row.ActorKind $Row.ActivityDateTime
        }
        foreach ($Row in @($Results.SentMessages | Where-Object { $_.FromIP })) {
            & $New $Row.FromIP 'Sent mail' $MassMail 'User' $Row.Received
        }
        foreach ($Row in @($Results.MailActivity | Where-Object { $_.ClientIP })) {
            & $New $Row.ClientIP "Mailbox $($Row.Operation)" $false $Row.ActorKind $Row.FirstSeen $Row.SessionIds
        }
    )
}
