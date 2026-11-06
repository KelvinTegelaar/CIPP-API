function Get-CIPPNhiScore {
    <#
    .SYNOPSIS
        Scores a non-human identity (NHI) compromise investigation.
    .DESCRIPTION
        Pure function over the run's results. Like the BEC score, every signal that fires adds its weight once
        (score.weights in Config/NhiHeuristics.json) and the total against score.thresholds is the evidence level:
        how sure we are the app is compromised. Unlike a user, an app's access ranges from reading a profile to
        running the tenant, so the case level crosses the evidence with the highest impact the app permission
        exposure report gives the app's access (impactMatrix): strong evidence against an app that can read one
        mailbox is a Medium case, moderate evidence against an app holding Global Administrator a High one.

        AttackerWorkload counts only when an attacker address is corroborated: confirmed on CIPP's block list, or
        judged LikelyAttacker because it signed in with a flagged credential or for a new Azure resource. On
        network heuristics alone, mail and file activity from that address is not counted, and the breakdown
        says so. Mass mailbox and file access count only the mailboxes, and files on sites, the app did not reach
        in the baseline before the window: a backup or archiving app reaches everything every day. A credential
        that replaced an expiring or removed one (Rotation) is not a new credential. The volume signals compare
        the daily rate of sign-ins, and of mail and file operations, with the baseline's; they need a complete
        baseline, an uncapped count and score.volumeMinimum events in the window. Mail sent and anonymous links
        created count only when the app did neither before the window; a jump in how much it sends is the volume signal's.
    .PARAMETER Results
        The run's results payload (Push-NHIRun).
    .PARAMETER Heuristics
        The NHI heuristics object.
    .OUTPUTS
        { Value, EvidenceLevel, Impact, Level, Thresholds, Breakdown[{ Signal, Description, Weight, Count, Applied }] }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Results,
        [Parameter(Mandatory = $true)]$Heuristics
    )

    $Cfg = $Heuristics.score
    $W = $Cfg.weights
    $HighThreshold = [int]($Cfg.thresholds.high ?? 7)
    $MediumThreshold = [int]($Cfg.thresholds.medium ?? 4)
    $Start = if ($Results.StartDate) { ([datetime]$Results.StartDate).ToUniversalTime() } else { [datetime]::MinValue }
    $InWindow = { param($When) $When -and ([datetime]$When).ToUniversalTime() -ge $Start }
    $Comparer = [System.StringComparer]::OrdinalIgnoreCase

    $Exposure = $Results.Exposure
    $Credentials = @($Exposure.CredentialDetails | Where-Object { $_ -and $_.Purpose -eq 'Sign-in' -and -not $_.Expired })
    $FlaggedKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($Results.FlaggedKeyIds) | Where-Object { $_ }), $Comparer)
    $Changes = @($Results.Changes | Where-Object { $_ -and $_.InWindow })
    $Actions = @($Results.DirectoryActions | Where-Object { $_ -and $_.InWindow })
    $Verdicts = @($Results.IPVerdicts | Where-Object { $_ })
    $HasBaseline = [int]$Results.Baseline.Total -ge [int]($Heuristics.baseline.minSignIns ?? 10)
    $Known = @{}
    foreach ($Name in 'KeyIds', 'Resources', 'AttachedResources') {
        $Known[$Name] = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($Results.Baseline.$Name) | Where-Object { $_ } | ForEach-Object { [string]$_ }), $Comparer)
    }
    $AttackerIPs = @($Verdicts | Where-Object { $_.Verdict -in 'Compromised', 'LikelyAttacker' })
    # an attacker address backed by more than network heuristics (see DESCRIPTION)
    $Corroborated = @($AttackerIPs | Where-Object { $_.Verdict -eq 'Compromised' -or @($_.Reasons | Where-Object { $_.Code -in 'FlaggedCredential', 'NewAttachedResource' }).Count -gt 0 }).Count -gt 0
    $AttackerSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($AttackerIPs.IP | Where-Object { $_ }), $Comparer)
    $ConsentUsers = @($Results.Consents | Where-Object { $_ -and (& $InWindow $_.ActivityDateTime) } | ForEach-Object { [string]$_.User } | Where-Object { $_ } | Select-Object -Unique)
    $Workload = $Results.WorkloadSummary
    # Elevation: high-impact access the app granted, to itself, another app or a user. An app that already granted it
    # before the window provisions access (it is a tool for that), and CIPP's own app grants as part of managing the tenant.
    $Elevations = @($Actions | Where-Object { $_.Kind -eq 'Elevation' -and $_.Impact -in 'High', 'Critical' })
    $ProvisionsAccess = @($Results.DirectoryActions | Where-Object { $_ -and -not $_.InWindow -and $_.Kind -eq 'Elevation' -and $_.Impact -in 'High', 'Critical' -and $_.Recipient -ne 'Self' }).Count -gt 0
    $IsCipp = [bool]$Results.Subject.IsCippApp
    # A rotation (a credential replacing one that expires or was removed) is the app's own new credential.
    $Rotations = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Credentials | Where-Object { $_.Flags -contains 'Rotation' } | ForEach-Object { [string]$_.KeyId }), $Comparer)
    # Reach new to the app: mailboxes, and files on sites, it did not reach before the window. Without that baseline
    # (the audit log before the window could not be read) everything it reached counts.
    $WorkloadBaseline = $Results.WorkloadBaseline
    $KnownMailboxes = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($WorkloadBaseline.Mailboxes) | Where-Object { $_ } | ForEach-Object { [string]$_ }), $Comparer)
    $KnownSites = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($WorkloadBaseline.Sites) | Where-Object { $_ } | ForEach-Object { [string]$_ }), $Comparer)
    $NewMailboxes = if ($WorkloadBaseline) { @($Results.WorkloadActivity.Mailboxes | Where-Object { $_.Mailbox -and -not $KnownMailboxes.Contains([string]$_.Mailbox) }).Count } else { [int]$Workload.MailboxCount }
    # Volume: the window's daily rate as a multiple of the baseline's. A capped count is a floor, not a rate, so it is not compared.
    $SpikeFactor = [double]($Cfg.volumeSpikeFactor ?? 5)
    $VolumeMinimum = [int]($Cfg.volumeMinimum ?? 50)
    $WindowDays = [Math]::Max(1, [int]$Results.AnalysisWindowDays)
    $BaselineDays = [Math]::Max(1, [int]$Results.BaselineDays)
    $SignInRatio = if ($HasBaseline -and -not $Results.SignInSummary.Capped -and -not $Results.Baseline.Capped -and [int]$Results.SignInSummary.Total -ge $VolumeMinimum) {
        ([int]$Results.SignInSummary.Total / $WindowDays) / ([int]$Results.Baseline.Total / $BaselineDays)
    } else { 0 }
    $WindowOperations = [int](@($Results.WorkloadActivity.ByOperation | ForEach-Object { [int]$_.Count }) | Measure-Object -Sum).Sum
    $BaselineOperations = [int]$WorkloadBaseline.Operations
    $WorkloadRatio = if ($WorkloadBaseline.Complete -and $BaselineOperations -gt 0 -and $WindowOperations -ge $VolumeMinimum) {
        ($WindowOperations / $WindowDays) / ($BaselineOperations / $BaselineDays)
    } else { 0 }
    $NewFiles = if ($WorkloadBaseline) { [int](@($Results.WorkloadActivity.Sites | Where-Object { $_.Site -and -not $KnownSites.Contains([string]$_.Site) } | ForEach-Object { [int]$_.FileCount }) | Measure-Object -Sum).Sum } else { [int]$Workload.FileCount }
    $Risk = $Results.RiskState

    $Stats = [ordered]@{
        RogueAppMatch                = [int][bool]$Results.RogueMatch
        DisabledByMicrosoft          = [int][bool]$Exposure.DisabledByMicrosoftStatus
        ConfirmedCompromised         = [int]($Risk.riskState -eq 'confirmedCompromised')
        RiskyHigh                    = [int]($Risk.riskState -eq 'atRisk' -and $Risk.riskLevel -eq 'high')
        RiskyMedium                  = [int]($Risk.riskState -eq 'atRisk' -and $Risk.riskLevel -eq 'medium')
        RiskyLow                     = [int]($Risk.riskState -eq 'atRisk' -and $Risk.riskLevel -eq 'low')
        RiskDetections               = @($Results.RiskDetections | Where-Object { $_ -and (& $InWindow ($_.activityDateTime ?? $_.detectedDateTime)) }).Count
        CredentialOnMicrosoftApp     = [int](($Exposure.IsMicrosoftApp -or $Exposure.IsCippApp) -and [int]$Exposure.ServicePrincipalCredentialCount -gt 0)
        CredentialAdded              = @($Credentials | Where-Object { $_.Flags -contains 'AddedRecently' -and $_.Flags -notcontains 'Rotation' -and (& $InWindow $_.AddedDateTime) }).Count
        CredentialAddedByApp         = @($Credentials | Where-Object { $_.Flags -contains 'AddedByApp' }).Count
        CredentialBackdated          = @($Credentials | Where-Object { $_.Flags -contains 'Backdated' }).Count
        UntrustedFederatedCredential = @($Credentials | Where-Object { $_.Flags -contains 'UntrustedIssuer' }).Count
        FederatedCredentialChanged   = @($Changes | Where-Object Kind -EQ 'FederatedCredential').Count
        OwnerAdded                   = @($Changes | Where-Object Kind -EQ 'Owner').Count
        RedirectUriChanged           = @($Changes | Where-Object Kind -EQ 'RedirectUri').Count
        AudienceChanged              = @($Changes | Where-Object Kind -EQ 'Audience').Count
        AccessGranted                = @($Changes | Where-Object { $_.Kind -eq 'Grant' -and -not $_.ByApp }).Count
        # an app granting itself access is self elevation, counted once there
        AccessGrantedByApp           = @($Changes | Where-Object { $_.Kind -eq 'Grant' -and $_.ByApp -and -not $_.BySelf }).Count
        NameImpersonation            = [int][bool]$Exposure.ImpersonatedProduct
        DormantAwakened              = [int]([bool]$Results.Dormant -and [int]$Results.SignInSummary.Success -gt 0)
        AttackerIPs                  = @($AttackerIPs | Where-Object { $_.SuccessfulSignIns -gt 0 -or $_.Activities -gt 0 }).Count
        SuspiciousIPs                = @($Verdicts | Where-Object { $_.Verdict -eq 'Suspicious' -and $_.SuccessfulSignIns -gt 0 }).Count
        FlaggedCredentialUsed        = @($Results.SignInsByCredential | Where-Object { $_.KeyId -and $FlaggedKeys.Contains([string]$_.KeyId) -and $_.Success -gt 0 }).Count
        NewCredentialInUse           = if ($HasBaseline) { @($Results.SignInsByCredential | Where-Object { $_.KeyId -and $_.Success -gt 0 -and -not $Known.KeyIds.Contains([string]$_.KeyId) -and -not $FlaggedKeys.Contains([string]$_.KeyId) -and -not $Rotations.Contains([string]$_.KeyId) }).Count } else { 0 }
        FailedCredentialAttempts     = @($Verdicts | Where-Object { @($_.Reasons.Code) -contains 'CredentialFailures' -and @($_.Reasons.Code) -notcontains 'BaselineAddress' }).Count
        NewResourceAccess            = if ($HasBaseline) { @(@($Results.SignInSummary.Resources) | Where-Object { $_ -and -not $Known.Resources.Contains([string]$_) }).Count } else { 0 }
        NewAttachedResource          = if ($HasBaseline) { @(@($Results.SignInSummary.AttachedResources) | Where-Object { $_ -and -not $Known.AttachedResources.Contains([string]$_) }).Count } else { 0 }
        ConsentBurst                 = $ConsentUsers.Count
        # app persistence (apps created, credentials or owners on other apps) is scored on its own, not again as a directory change
        CriticalDirectoryActions     = @($Actions | Where-Object { $_.Severity -eq 'Critical' -and $_.Kind -eq 'Directory' -and -not $_.Lateral }).Count
        LateralCredentialAdds        = @($Actions | Where-Object { $_.Lateral }).Count
        AppsCreated                  = @($Actions | Where-Object { $_.CreatedApp }).Count
        FlaggedDirectoryActions      = @($Actions | Where-Object { $_.Severity -eq 'Flagged' -and $_.Kind -eq 'Directory' }).Count
        SelfElevation                = @($Elevations | Where-Object Recipient -EQ 'Self').Count
        AppElevation                 = @($Elevations | Where-Object Recipient -EQ 'App').Count
        UserElevation                = @($Elevations | Where-Object Recipient -EQ 'User').Count
        ElevationChain               = [int]($Elevations.Count -gt 0 -and @($Actions | Where-Object Kind -EQ 'AppPersistence').Count -gt 0)
        InboxRulesByApp              = [int]$Workload.RuleCount
        MassMailboxAccess            = $NewMailboxes
        MassFileAccess               = $NewFiles
        # sending mail or creating anyone-links the app did not do before the window; without a baseline every one counts
        NewMailSending               = if (-not $WorkloadBaseline -or [int]$WorkloadBaseline.SendCount -eq 0) { [int]$Workload.SendCount } else { 0 }
        NewAnonymousLinks            = if (-not $WorkloadBaseline -or [int]$WorkloadBaseline.AnonymousLinkCount -eq 0) { [int]$Workload.AnonymousLinkCount } else { 0 }
        SignInVolumeSpike            = [int][Math]::Floor($SignInRatio)
        WorkloadVolumeSpike          = [int][Math]::Floor($WorkloadRatio)
        AttackerWorkload             = @($Results.WorkloadActivity.ByIP | Where-Object { $_.IP -and $AttackerSet.Contains([string]$_.IP) } | ForEach-Object { [int]$_.Count } | Measure-Object -Sum).Sum
    }
    $ConsentBurstUsers = [int]($Cfg.consentBurstUsers ?? 3)
    $MassMailboxes = [int]($Cfg.massMailboxes ?? 25)
    $MassFiles = [int]($Cfg.massFiles ?? 100)
    $Descriptions = @{
        RogueAppMatch                = 'The app is in the rogue-app catalog (CIPP and the Huntress feed)'
        DisabledByMicrosoft          = 'Microsoft disabled the app as malicious or abusive'
        ConfirmedCompromised         = 'Identity Protection: an administrator confirmed the service principal compromised'
        RiskyHigh                    = 'Identity Protection: service principal at high risk'
        RiskyMedium                  = 'Identity Protection: service principal at medium risk'
        RiskyLow                     = 'Identity Protection: service principal at low risk'
        RiskDetections               = 'Identity Protection raised risk detections for the app in the window'
        CredentialOnMicrosoftApp     = "A sign-in credential sits on a Microsoft or CIPP app's service principal, which neither ever adds"
        CredentialAdded              = 'A sign-in credential was added to the app in the window, other than a rotation'
        CredentialAddedByApp         = 'A credential was added to the app by another app'
        CredentialBackdated          = "A credential's start date was set before it was added"
        UntrustedFederatedCredential = 'A federated credential trusts an issuer CIPP does not recognise, or another Entra tenant'
        FederatedCredentialChanged   = 'A federated credential was added or changed in the window'
        OwnerAdded                   = 'An owner, who can add credentials, was added in the window'
        RedirectUriChanged           = 'The redirect URIs, where sign-in codes and tokens go, were changed in the window'
        AudienceChanged              = 'The app was opened to other organisations in the window'
        AccessGranted                = 'A permission, consent or directory role was given to the app in the window'
        AccessGrantedByApp           = 'A permission, consent or directory role was given to the app by an app, or by itself'
        NameImpersonation            = 'An unverified app owned elsewhere is named like a Microsoft product'
        DormantAwakened              = "The app had no sign-ins in the $([int]$Results.BaselineDays) days before the window, then signed in during it"
        AttackerIPs                  = 'Sign-ins or activity from addresses judged to be an attacker'
        SuspiciousIPs                = 'Successful sign-ins from addresses judged suspicious'
        FlaggedCredentialUsed        = 'A flagged credential (added recently, by another app, backdated or trusting an unknown issuer) signed in'
        NewCredentialInUse           = 'A credential the app never used before the window signed in, other than a rotation'
        FailedCredentialAttempts     = 'Sign-ins with a wrong, expired or revoked credential from addresses the app does not use'
        NewResourceAccess            = 'The app requested tokens for an API it never used before the window'
        NewAttachedResource          = 'The managed identity was used by an Azure resource it was never used by before'
        ConsentBurst                 = "$ConsentBurstUsers or more users consented to the app in the window"
        CriticalDirectoryActions     = 'The app changed domain federation, roles, Conditional Access, tenant policy or app ownership'
        LateralCredentialAdds        = 'App persistence: the app added a credential or owner to another app'
        AppsCreated                  = 'App persistence: the app created an application or service principal'
        SelfElevation                = 'Elevation: the app gave itself a high-impact permission or directory role'
        AppElevation                 = 'Elevation: the app gave another app a high-impact permission or directory role'
        UserElevation                = 'Elevation: the app gave a user a high-impact permission or directory role'
        ElevationChain               = 'Elevation and app persistence in the same window: an attack sequence, not a coincidence'
        FlaggedDirectoryActions      = 'The app created, changed or reset users, groups, consents or security info'
        InboxRulesByApp              = 'The app created or changed inbox rules'
        MassMailboxAccess            = "The app reached $MassMailboxes or more mailboxes it did not reach in the $([int]$Results.BaselineDays) days before the window"
        MassFileAccess               = "The app touched $MassFiles or more files on sites it did not reach in the $([int]$Results.BaselineDays) days before the window"
        NewMailSending               = "The app sent mail, which it did not do in the $([int]$Results.BaselineDays) days before the window"
        NewAnonymousLinks            = "The app created anonymous ('anyone') sharing links, which it did not do in the $([int]$Results.BaselineDays) days before the window"
        SignInVolumeSpike            = "The app signed in $SpikeFactor or more times as often a day as it did before the window (count: times its usual rate)"
        WorkloadVolumeSpike          = "The app's mail and file activity was $SpikeFactor or more times its daily rate before the window (count: times its usual rate)"
        AttackerWorkload             = 'Mail or file activity from an attacker address'
    }

    $Breakdown = [System.Collections.Generic.List[object]]::new()
    $Total = 0
    foreach ($Name in $Stats.Keys) {
        $Value = [int]$Stats[$Name]
        $Applied = switch ($Name) {
            'ConsentBurst' { $Value -ge $ConsentBurstUsers }
            'MassMailboxAccess' { $Value -ge $MassMailboxes }
            'MassFileAccess' { $Value -ge $MassFiles }
            { $_ -in 'SignInVolumeSpike', 'WorkloadVolumeSpike' } { $Value -ge $SpikeFactor }
            'AttackerWorkload' { $Value -gt 0 -and $Corroborated }
            'SelfElevation' { $Value -gt 0 -and -not $IsCipp }
            { $_ -in 'AppElevation', 'UserElevation', 'ElevationChain' } { $Value -gt 0 -and -not $IsCipp -and -not $ProvisionsAccess }
            default { $Value -gt 0 }
        }
        $Weight = [int]($W.$Name ?? 0)
        if ($Applied) { $Total += $Weight }
        $Breakdown.Add([pscustomobject]@{
                Signal      = $Name
                Description = if ($Name -eq 'AttackerWorkload' -and $Value -gt 0 -and -not $Corroborated) {
                    "$($Descriptions[$Name]) - not counted: no attacker address is backed by a flagged credential, a new Azure resource or the block list"
                } elseif ($Name -in @('SelfElevation', 'AppElevation', 'UserElevation', 'ElevationChain') -and $Value -gt 0 -and $IsCipp) {
                    "$($Descriptions[$Name]) - not counted: CIPP's own app grants access as part of managing the tenant"
                } elseif ($Name -in @('AppElevation', 'UserElevation', 'ElevationChain') -and $Value -gt 0 -and $ProvisionsAccess) {
                    "$($Descriptions[$Name]) - not counted: the app granted high-impact access before the window too, so it provisions access"
                } elseif ($Name -in @('MassMailboxAccess', 'MassFileAccess', 'NewMailSending', 'NewAnonymousLinks') -and -not $WorkloadBaseline -and $Value -gt 0) {
                    "$($Descriptions[$Name]) - every one counted: the audit log before the window could not be read"
                } else {
                    $Descriptions[$Name]
                }
                Weight      = $Weight
                Count       = $Value
                Applied     = [bool]$Applied
            })
    }

    $EvidenceLevel = if ($Total -ge $HighThreshold) { 'High' } elseif ($Total -ge $MediumThreshold) { 'Medium' } else { 'Low' }
    # an app holding nothing catalogued has Low impact; without the exposure row its reach is unknown: rated as Medium, never as harmless
    $Impact = if ($Exposure.HighestImpact) { [string]$Exposure.HighestImpact } elseif ($Exposure) { 'Low' } else { 'Medium' }
    $Level = [string]$Heuristics.impactMatrix.$EvidenceLevel.$Impact
    if (-not $Level) { $Level = $EvidenceLevel }
    return [pscustomobject]@{
        Value         = [int]$Total
        EvidenceLevel = $EvidenceLevel
        Impact        = $Impact
        ImpactKnown   = [bool]$Exposure
        Level         = $Level
        Thresholds    = [pscustomobject]@{ High = $HighThreshold; Medium = $MediumThreshold }
        Breakdown     = $Breakdown.ToArray()
    }
}
