function Get-CIPPBaselineColleagueImpersonationAlertState {
    <#
    .SYNOPSIS
        Prepare hook for ColleagueImpersonationAlert: the five display-name impersonation
        transport rules.
    .DESCRIPTION
        The expected state is DYNAMIC: each rule's header patterns are computed from the
        tenant's live mailbox display names (grouped A-E/F-J/K-O/P-T/U-Z), so the grade is
        per-rule "exists AND patterns match", the classic's exact semantics. Everything
        reads from CIPPDb caches - Mailboxes for display names (user+shared, enabled, not
        keyword-excluded), ExoAcceptedDomains for the automatic domain exemptions, and
        ExoTransportRules for the rules themselves. The optional display name separator
        adds the short name (text before the separator) as a second pattern per user, and
        an empty letter group carries its "($range)" placeholder pattern - both classic
        behaviours the write depends on.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Mailboxes = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Mailboxes')
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoTransportRules')
    $AcceptedDomains = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains')
    if ($Mailboxes.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Mailboxes')) {
        return @{ Current = $null }
    }
    if ($AcceptedDomains.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoAcceptedDomains')) {
        return @{ Current = $null }
    }

    $V = $Item.Variables
    $DisplayNameSeparator = "$($V.displayNameSeparator)"
    $Unwrap = { param($Value) @(@($Value) | ForEach-Object { if ($_ -is [string]) { $_ } else { [string]($_.value ?? $_.label) } } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
    $ExcludeKeywords = @(& $Unwrap $V.excludedMailboxes)
    $AdditionalExemptSenders = @(& $Unwrap $V.additionalExemptSenders)

    $AutoExemptDomains = @($AcceptedDomains | ForEach-Object { "$($_.DomainName)" } |
            Where-Object { $_ -and $_ -notmatch '\.onmicrosoft\.com$|\.exclaimer\.cloud$' })

    $DisplayNames = @($Mailboxes | Where-Object {
            $Mailbox = $_
            if ("$($Mailbox.recipientTypeDetails)" -notin @('UserMailbox', 'SharedMailbox')) { return $false }
            if ($Mailbox.AccountDisabled -eq $true) { return $false }
            if ([string]::IsNullOrWhiteSpace("$($Mailbox.displayName)")) { return $false }
            foreach ($Keyword in $ExcludeKeywords) {
                if ("$($Mailbox.displayName)" -match [regex]::Escape($Keyword)) { return $false }
            }
            $true
        } | ForEach-Object { "$($_.displayName)" })

    $Groups = [ordered]@{
        'A-E' = '^[A-Ea-e]'
        'F-J' = '^[F-Jf-j]'
        'K-O' = '^[K-Ok-o]'
        'P-T' = '^[P-Tp-t]'
        'U-Z' = '^[U-Zu-z]'
    }

    $RuleStates = [System.Collections.Generic.List[object]]::new()
    $Expected = [PSCustomObject]@{}
    $Current = [PSCustomObject]@{}
    foreach ($Entry in $Groups.GetEnumerator()) {
        $Range = $Entry.Key
        $Pattern = $Entry.Value
        $RuleName = "($Range) Colleague Impersonation Alert"
        $Names = @($DisplayNames | Where-Object { $_ -match $Pattern } | ForEach-Object {
                $FullName = $_.Trim()
                [regex]::Escape($FullName)
                if (-not [string]::IsNullOrWhiteSpace($DisplayNameSeparator)) {
                    $SeparatorPattern = [regex]::Escape($DisplayNameSeparator.Trim())
                    if ($FullName -match $SeparatorPattern) {
                        $ShortName = ($FullName -split "\s*$SeparatorPattern\s*", 2)[0].Trim()
                        if (-not [string]::IsNullOrWhiteSpace($ShortName) -and $ShortName -ne $FullName) {
                            [regex]::Escape($ShortName)
                        }
                    }
                }
            } | Sort-Object -Unique)
        if ($Names.Count -eq 0) { $Names = @([regex]::Escape("($Range)")) }

        $Existing = $Rules | Where-Object { "$($_.Name)" -eq $RuleName } | Select-Object -First 1
        $NamesMatch = $false
        if ($null -ne $Existing) {
            $ExistingPatterns = @($Existing.HeaderMatchesPatterns | ForEach-Object { "$_" })
            $NamesMatch = (($Names | Sort-Object) -join "`n") -eq (($ExistingPatterns | Sort-Object) -join "`n")
        }

        $RuleStates.Add([PSCustomObject]@{
                RuleName             = $RuleName
                Range                = $Range
                Names                = @($Names)
                RuleExists           = ($null -ne $Existing)
                ExistingExemptSender = @($Existing.ExceptIfFromAddressContainsWords | ForEach-Object { "$_" })
                ExistingExemptDomain = @($Existing.ExceptIfSenderDomainIs | ForEach-Object { "$_" })
                ExistingDisclaimer   = "$($Existing.ApplyHtmlDisclaimerText)"
            })
        $Expected | Add-Member -NotePropertyName $RuleName -NotePropertyValue $true
        $Current | Add-Member -NotePropertyName $RuleName -NotePropertyValue (($null -ne $Existing) -and $NamesMatch)
    }

    # Carried for the executor: the computed patterns and the existing exemptions to merge.
    $Current | Add-Member -NotePropertyName 'ruleStates' -NotePropertyValue @($RuleStates)
    $Current | Add-Member -NotePropertyName 'autoExemptDomains' -NotePropertyValue @($AutoExemptDomains)
    $Current | Add-Member -NotePropertyName 'additionalExemptSenders' -NotePropertyValue @($AdditionalExemptSenders)

    @{ Expected = $Expected; Current = $Current }
}
