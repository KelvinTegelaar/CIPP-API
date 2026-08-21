function Invoke-CIPPBaselineColleagueImpersonationAlert {
    <#
    .SYNOPSIS
        ColleagueImpersonationAlert executor: creates or updates the five impersonation
        transport rules.
    .DESCRIPTION
        The classic's merge-preserving write. Per rule: the exempt sender list is the
        configured additions PLUS whatever the existing rule already carries, the exempt
        domain list is the accepted-domain exemptions PLUS the existing rule's - manual
        operator exemptions are never stripped. The disclaimer HTML falls back to an
        existing rule's when the baseline leaves it blank, and a rule that cannot fall
        back refuses to write rather than deploying an empty banner.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $RuleHtml = "$($Remediate.disclaimerHtml)"
    if ([string]::IsNullOrWhiteSpace($RuleHtml)) {
        $Fallback = @($Current.ruleStates | Where-Object { -not [string]::IsNullOrWhiteSpace("$($_.ExistingDisclaimer)") }) | Select-Object -First 1
        if ($Fallback) {
            $RuleHtml = "$($Fallback.ExistingDisclaimer)"
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Disclaimer HTML not configured - using the HTML from an existing rule.' -Sev 'Info'
        } else {
            throw 'Disclaimer HTML is not configured and no existing rule carries one - configure the Disclaimer HTML field on the baseline.'
        }
    }

    $Failures = 0
    $RuleStates = @($Current.ruleStates)
    foreach ($RuleState in $RuleStates) {
        $SeenSenders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $ExemptSenders = [System.Collections.Generic.List[string]]::new()
        foreach ($Address in @($Current.additionalExemptSenders) + @($RuleState.ExistingExemptSender)) {
            $Trimmed = "$Address".Trim()
            if (-not [string]::IsNullOrWhiteSpace($Trimmed) -and $SeenSenders.Add($Trimmed)) { $ExemptSenders.Add($Trimmed) }
        }
        $SeenDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $ExemptDomains = [System.Collections.Generic.List[string]]::new()
        foreach ($Domain in @($Current.autoExemptDomains) + @($RuleState.ExistingExemptDomain)) {
            $Trimmed = "$Domain".Trim()
            if (-not [string]::IsNullOrWhiteSpace($Trimmed) -and $SeenDomains.Add($Trimmed)) { $ExemptDomains.Add($Trimmed) }
        }

        $CmdParams = @{
            FromScope                         = 'NotInOrganization'
            ApplyHtmlDisclaimerLocation       = 'Prepend'
            ApplyHtmlDisclaimerFallbackAction = 'Wrap'
            ApplyHtmlDisclaimerText           = $RuleHtml
            HeaderMatchesMessageHeader        = 'From'
            HeaderMatchesPatterns             = @($RuleState.Names)
            Comments                          = "CIPP managed rule ($($RuleState.Range)) - Letters $($RuleState.Range)"
        }
        # Both exception lists only when non-empty: Exchange rejects an empty
        # ExceptIfSenderDomainIs outright, which broke every onmicrosoft-only tenant
        # (their sole accepted domain is filtered off the auto-exemption list).
        if ($ExemptDomains.Count -gt 0) { $CmdParams['ExceptIfSenderDomainIs'] = @($ExemptDomains) }
        if ($ExemptSenders.Count -gt 0) { $CmdParams['ExceptIfFromAddressContainsWords'] = @($ExemptSenders) }

        try {
            if ($RuleState.RuleExists) {
                $CmdParams['Identity'] = "$($RuleState.RuleName)"
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-TransportRule' -cmdParams $CmdParams -UseSystemMailbox $true
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated the impersonation rule '$($RuleState.RuleName)' ($(@($RuleState.Names).Count) pattern(s))." -Sev 'Info'
            } else {
                $CmdParams['Name'] = "$($RuleState.RuleName)"
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-TransportRule' -cmdParams $CmdParams -UseSystemMailbox $true
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created the impersonation rule '$($RuleState.RuleName)' ($(@($RuleState.Names).Count) pattern(s))." -Sev 'Info'
            }
        } catch {
            $Failures++
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to write the impersonation rule '$($RuleState.RuleName)': $($_.Exception.Message)" -Sev 'Error'
        }
    }
    if ($RuleStates.Count -gt 0 -and $Failures -ge $RuleStates.Count) {
        throw "Every impersonation rule write failed for $TenantFilter - see the log for the first error."
    }
}
