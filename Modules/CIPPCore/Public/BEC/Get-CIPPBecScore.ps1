function Get-CIPPBecScore {
    <#
    .SYNOPSIS
        Computes the BEC threat score and its breakdown from a results payload.
    .DESCRIPTION
        Pure function: takes the results object Push-BECRun assembles and the heuristics (weights +
        thresholds) and returns { Value, Level, Thresholds, Breakdown }. The first fifteen signals
        reproduce the additive score the PDF report computed client-side before the score moved
        server-side - same counts, same weights, same High/Medium thresholds - so old and new reports
        agree. The Full-scope signals (delegations, grants, transport rules, add-ins, received mail,
        Defender, directory audits, registered devices, non-interactive sign-ins, mail activity, risk
        state) add their weights only when their data is present in the payload.
    .PARAMETER Results
        The BEC results object.
    .PARAMETER Heuristics
        The BEC heuristics object (score.weights, score.thresholds, inboxRules.suspiciousFolderPattern).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Results,
        [Parameter(Mandatory = $true)]$Heuristics
    )

    $W = $Heuristics.score.weights
    $HighThreshold = [int]($Heuristics.score.thresholds.high ?? 7)
    $MediumThreshold = [int]($Heuristics.score.thresholds.medium ?? 4)
    $NewUsersThreshold = [int]($Heuristics.score.newUsersThreshold ?? 5)
    $WindowDays = [int]($Results.AnalysisWindowDays ?? $Heuristics.window.days ?? 7)
    $SuspiciousFolder = [string]($Heuristics.inboxRules.suspiciousFolderPattern ?? 'RSS')

    $ExtractedAt = try { ([datetime]$Results.ExtractedAt).ToUniversalTime() } catch { (Get-Date).ToUniversalTime() }
    $WindowStart = $ExtractedAt.AddDays(-$WindowDays)
    $InWindow = { param($Value) if (-not $Value) { return $false }; try { ([datetime]$Value).ToUniversalTime() -ge $WindowStart } catch { $false } }
    $Count = { param($Value) if ($null -eq $Value) { 0 } else { @($Value).Count } }

    # --- the original fifteen signals (stats derivation mirrors the report) ---
    $NewRules = @($Results.NewRules)
    $LocationAnalysis = $Results.LocationAnalysis
    $Stats = [ordered]@{
        NewRules                       = & $Count $Results.NewRules
        InboxRuleChanges               = & $Count $Results.InboxRuleChanges
        PermissionChanges              = & $Count $Results.MailboxPermissionChanges
        PermissionChangesTargetingUser = @($Results.MailboxPermissionChanges | Where-Object { $_.TargetsSuspect -eq $true }).Count
        NewApps                        = & $Count $Results.AddedApps
        NewUsers                       = & $Count $Results.NewUsers
        SafelistChanges                = & $Count $Results.SafelistChanges
        SuspiciousRules                = @($NewRules | Where-Object { $_.Suspicious -eq $true -or [string]$_.MoveToFolder -clike "*$SuspiciousFolder*" }).Count
        MaliciousApps                  = @($Results.AddedApps | Where-Object { $_.MaliciousMatch }).Count + (& $Count $Results.MaliciousSPs)
        ForeignSuccessfulSignIns       = [int]($LocationAnalysis.ForeignSuccessfulSignInCount ?? 0)
        ForeignActivity                = [int]($LocationAnalysis.ForeignRuleChangeCount ?? 0) + [int]($LocationAnalysis.ForeignSafelistChangeCount ?? 0) + [int]($LocationAnalysis.ForeignSharingChangeCount ?? 0) + [int]($LocationAnalysis.ForeignSentMessageCount ?? 0)
        AnonymousLinks                 = @($Results.SharingChanges | Where-Object { [string]$_.Operation -like 'AnonymousLink*' }).Count
        MassMail                       = if ($Results.SentMessageAnalysis.Flagged -eq $true) { 1 } else { 0 }
        RecentMfaMethods               = @($Results.MFADevices | Where-Object { & $InWindow $_.createdDateTime }).Count
        RecentIntuneDevices            = @($Results.IntuneDevices | Where-Object { & $InWindow $_.enrolledDateTime }).Count
        # --- Full-scope signals ---
        FlaggedDelegations             = @($Results.Delegations | Where-Object { $_.Flagged -eq $true }).Count
        RiskyUserGrants                = @($Results.UserGrants | Where-Object { $_.Risk -eq 'High' }).Count
        CatalogUserGrants              = @($Results.UserGrants | Where-Object { $_.Risk -eq 'CatalogMatch' }).Count
        RiskyTransportRuleChanges      = @($Results.TransportRuleChanges | Where-Object { $_.Flagged -eq $true }).Count
        FlaggedMailboxAddIns           = @($Results.MailboxAddIns | Where-Object { $_.Flagged -eq $true }).Count
        TyposquatSenders               = @($Results.ReceivedMailFindings | Where-Object { $_.FindingType -eq 'PossibleTyposquat' }).Count
        DefenderDetections             = @($Results.DefenderDetections | Where-Object { $_.Delivered -eq $true }).Count
        FlaggedDirectoryAudits         = @($Results.DirectoryAudits | Where-Object { $_.Flagged -eq $true }).Count
        RecentRegisteredDevices        = @($Results.RegisteredDevices | Where-Object { $_.RegisteredInWindow -eq $true }).Count
        ForeignNonInteractiveSignIns   = @($Results.NonInteractiveSignIns | Where-Object { $_.ForeignLocation -eq $true -and $_.Status -eq 'Success' }).Count
        SuspiciousMailActivity         = [int]([bool]($Results.MailActivitySummary.HardDeleteExceeded -eq $true)) + @($Results.MailActivity | Where-Object { $_.Operation -eq 'MailItemsAccessed' -and $_.ForeignLocation -eq $true }).Count
        RiskyUserHigh                  = if ($Results.RiskState.Listed -eq $true -and $Results.RiskState.RiskState -eq 'atRisk' -and $Results.RiskState.RiskLevel -eq 'high') { 1 } else { 0 }
        RiskyUserMedium                = if ($Results.RiskState.Listed -eq $true -and $Results.RiskState.RiskState -eq 'atRisk' -and $Results.RiskState.RiskLevel -eq 'medium') { 1 } else { 0 }
        RiskyUserLow                   = if ($Results.RiskState.Listed -eq $true -and $Results.RiskState.RiskState -eq 'atRisk' -and $Results.RiskState.RiskLevel -eq 'low') { 1 } else { 0 }
        ConfirmedCompromised           = if ($Results.RiskState.RiskState -eq 'confirmedCompromised') { 1 } else { 0 }
        # addresses judged the attacker's (by an investigator, the CIPP list or the heuristics) that got in or acted
        AttackerIPs                    = @($Results.IPVerdicts | Where-Object { $_.Verdict -in @('Compromised', 'LikelyAttacker') -and ([int]$_.SuccessfulSignIns -gt 0 -or [int]$_.Activities -gt 0) }).Count
        # item-level activity counts only from addresses judged the attacker's, not merely suspicious or unknown
        AttackerMailAccess             = @($Results.AttackerMailActivity | Where-Object { $_.IPVerdict -in @('Compromised', 'LikelyAttacker') }).Count
        AttackerFileAccess             = @($Results.AttackerFileActivity | Where-Object { $_.IPVerdict -in @('Compromised', 'LikelyAttacker') }).Count
        AttackerForms                  = @($Results.FormsActivity | Where-Object { $_.Flagged -eq $true -and $_.IPVerdict -in @('Compromised', 'LikelyAttacker') }).Count
        OtherAccountsReached           = @($Results.BlastRadius | Where-Object { $_.Reached -eq $true }).Count
        DelegatedMailboxAttackerAccess = @($Results.AttackerMailActivity | Where-Object { $_.IPVerdict -in @('Compromised', 'LikelyAttacker') -and $_.MailboxOwner -and $Results.UserPrincipalName -and $_.MailboxOwner -ne $Results.UserPrincipalName } | ForEach-Object { $_.MailboxOwner } | Select-Object -Unique).Count
    }

    $Descriptions = @{
        NewRules                       = 'Inbox rules exist on the mailbox'
        InboxRuleChanges               = 'Inbox rules were created, changed or removed in the window'
        PermissionChangesTargetingUser = 'Mailbox permission changes targeted this mailbox'
        PermissionChanges              = 'Mailbox permission changes elsewhere in the tenant'
        NewApps                        = 'New service principals appeared in the tenant'
        NewUsers                       = "More than $NewUsersThreshold users were created in the window"
        SafelistChanges                = 'Trusted/blocked sender lists were changed'
        SuspiciousRules                = 'An inbox rule hides, forwards or deletes mail (or acts on all incoming mail)'
        MaliciousApps                  = 'Applications match the known-malicious catalog'
        ForeignSuccessfulSignIns       = 'Successful sign-ins from outside the usage location'
        ForeignActivity                = 'Rule, safelist, sharing or mail activity from outside the usage location'
        AnonymousLinks                 = 'Anonymous sharing links were created or changed'
        MassMail                       = 'Mass-mail pattern in sent messages'
        RecentMfaMethods               = 'MFA methods registered in the window'
        RecentIntuneDevices            = 'Intune devices enrolled in the window'
        FlaggedDelegations             = 'External, guest or catch-all mailbox delegations'
        RiskyUserGrants                = 'Consent grants with high-risk scopes from unverified publishers'
        CatalogUserGrants              = 'Consent grants to applications in the rogue-app catalog'
        RiskyTransportRuleChanges      = 'Transport rules with diversion or suppression actions changed in the window'
        FlaggedMailboxAddIns           = 'User-installed non-Microsoft mailbox add-ins'
        TyposquatSenders               = 'Mail received from look-alike sender domains'
        DefenderDetections             = 'Defender-classified threats delivered to the mailbox'
        FlaggedDirectoryAudits         = 'Security-info, consent or device registration events in the directory audit'
        RecentRegisteredDevices        = 'Entra devices registered in the window'
        ForeignNonInteractiveSignIns   = 'Successful non-interactive sign-ins from outside the usage location'
        SuspiciousMailActivity         = 'Excessive hard deletes or mailbox access from outside the usage location'
        RiskyUserHigh                  = 'Identity Protection: user at high risk'
        RiskyUserMedium                = 'Identity Protection: user at medium risk'
        RiskyUserLow                   = 'Identity Protection: user at low risk'
        ConfirmedCompromised           = 'Identity Protection: user confirmed compromised'
        AttackerIPs                    = 'Sign-ins or activity from addresses judged to be the attacker'
        AttackerMailAccess             = 'Mail opened, synced, deleted, moved or sent from an attacker address'
        AttackerFileAccess             = 'OneDrive/SharePoint files touched from an attacker address'
        AttackerForms                  = 'Microsoft Forms created, edited or shared from an attacker address'
        OtherAccountsReached           = 'Another account in the tenant signed in or acted from an attacker address'
        DelegatedMailboxAttackerAccess = "Another mailbox reached through this account's delegated access from an attacker address"
    }

    $Breakdown = [System.Collections.Generic.List[object]]::new()
    $Total = 0
    foreach ($Name in $Stats.Keys) {
        $Value = [int]$Stats[$Name]
        $Applied = switch ($Name) {
            'NewUsers' { $Value -gt $NewUsersThreshold }
            # a change to this mailbox outweighs unrelated tenant churn; only one of the two applies
            'PermissionChanges' { $Value -gt 0 -and [int]$Stats['PermissionChangesTargetingUser'] -eq 0 }
            default { $Value -gt 0 }
        }
        $Wt = [int]($W.$Name ?? 0)
        if ($Applied) { $Total = $Total + $Wt }
        $Breakdown.Add([pscustomobject]@{
                Signal      = $Name
                Description = $Descriptions[$Name]
                Weight      = $Wt
                Count       = $Value
                Applied     = [bool]$Applied
            })
    }

    $Level = if ($Total -ge $HighThreshold) { 'High' } elseif ($Total -ge $MediumThreshold) { 'Medium' } else { 'Low' }
    return [pscustomobject]@{
        Value      = [int]$Total
        Level      = $Level
        Thresholds = [pscustomobject]@{ High = $HighThreshold; Medium = $MediumThreshold }
        Breakdown  = $Breakdown.ToArray()
    }
}
