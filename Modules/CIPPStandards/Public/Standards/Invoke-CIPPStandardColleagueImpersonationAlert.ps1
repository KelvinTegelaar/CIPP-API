function Invoke-CIPPStandardColleagueImpersonationAlert {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ColleagueImpersonationAlert
    .SYNOPSIS
        (Label) Colleague Impersonation Alert Transport Rules
    .DESCRIPTION
        (Helptext) Creates/updates 5x Exchange Online transport rules (A-E, F-J, K-O, P-T, U-Z) that prepend an HTML disclaimer banner to inbound emails where the sender display name matches a mailbox in the organisation. Accepted tenant domains are always exempt automatically. Inactive users are removed and enabled users are added. Any manually configured sender or domain exemptions already present on existing rules are preserved.
        (DocsDescription) Creates five Exchange Online transport rules grouped by the first letter of user display names (A-E, F-J, K-O, P-T, U-Z). Each rule fires when an external sender's From header matches a display name in that group, prepends a configurable HTML warning banner, and skips emails from accepted organisational domains. Any manually configured sender or domain exemptions on existing rules are preserved when the standard runs. The disclaimer HTML is fully customisable via the standard settings.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Automatically alerts recipients when an email arrives from outside the organisation using a display name that matches an internal user - a common social-engineering technique. Five transport rules cover all display-name initial letters, keeping each rule within Exchange Online size limits. The disclaimer banner is prepended to the message body and directs users to verify authenticity before acting on the email.
        ADDEDCOMPONENT
            {"type":"heading","label":"Alert Banner (HTML)","required":false}
            {"type":"textField","name":"standards.ColleagueImpersonationAlert.disclaimerHtml","label":"Disclaimer HTML - Paste the full HTML for the warning banner","required":true}
            {"type":"heading","label":"Keyword Exclusions for Transport Rule","required":false}
            {"type":"autoComplete","name":"standards.ColleagueImpersonationAlert.excludedMailboxes","label":"Exclude mailboxes by keyword (e.g. any DisplayName containing 'Leaver')","multiple":true,"creatable":true,"required":false,"options":[]}
            {"type":"heading","label":"Exempt Senders (ExceptIfFromAddressContainsWords)","required":false}
            {"type":"autoComplete","name":"standards.ColleagueImpersonationAlert.additionalExemptSenders","label":"Additional exempt sender addresses (for example no-reply@teams.mail.microsoft)","multiple":true,"creatable":true,"required":false,"options":[]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-03-25
        POWERSHELLEQUIVALENT
            New-TransportRule / Set-TransportRule
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'ColleagueImpersonationAlert' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE')
    
    if ($TestResult -eq $false) {
        return $true 
    } #we're done.

    $ruleHtml = $Settings.disclaimerHtml

    $excludeKeywords = @(
        @($Settings.excludedMailboxes) | ForEach-Object {
            if ($_ -is [string]) { $_ } else { [string]($_.value ?? $_.label) }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $additionalExemptSenders = @(
        @($Settings.additionalExemptSenders) | ForEach-Object {
            if ($_ -is [string]) { $_ } else { [string]($_.value ?? $_.label) }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    try {
        $acceptedDomains = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AcceptedDomain'
        $autoExemptDomains = @(
            $acceptedDomains.DomainName |
            Where-Object { $_ -and $_ -notmatch '\.onmicrosoft\.com$|\.exclaimer\.cloud$' } |
            ForEach-Object { [string]$_ }
        )
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: could not retrieve accepted domains. Error: $ErrorMessage" -Sev Error
        return
    }

    try {
        $mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' `
            -cmdParams @{ ResultSize = 'Unlimited'; RecipientTypeDetails = @('UserMailbox', 'SharedMailbox') }
        $displayNames = @(
            $mailboxes | Where-Object {
                $mb = $_
                if ($mb.AccountDisabled -eq $true) { return $false }
                foreach ($kw in $excludeKeywords) {
                    if (-not [string]::IsNullOrWhiteSpace($mb.DisplayName) -and
                        $mb.DisplayName -match [regex]::Escape($kw)) { return $false }
                }
                return -not [string]::IsNullOrWhiteSpace($mb.DisplayName)
            } | Select-Object -ExpandProperty DisplayName
        )
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: could not retrieve mailboxes. Error: $ErrorMessage" -Sev Error
        return
    }

    $groups = [ordered]@{
        'A-E' = '^[A-Ea-e]'
        'F-J' = '^[F-Jf-j]'
        'K-O' = '^[K-Ok-o]'
        'P-T' = '^[P-Tp-t]'
        'U-Z' = '^[U-Zu-z]'
    }

    try {
        $existingRules = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TransportRule'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: could not retrieve transport rules. Error: $ErrorMessage" -Sev Error
        return
    }

    if ([string]::IsNullOrWhiteSpace($ruleHtml) -and $Settings.remediate -eq $true) {
        $fallbackRule = $existingRules | Where-Object {
            $_.Name -like '*Colleague Impersonation Alert*' -and
            -not [string]::IsNullOrWhiteSpace($_.ApplyHtmlDisclaimerText)
        } | Select-Object -First 1

        if ($fallbackRule) {
            $ruleHtml = $fallbackRule.ApplyHtmlDisclaimerText
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'ColleagueImpersonationAlert: disclaimerHtml not in settings; using HTML from existing rule.' -Sev Info
        } else {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'ColleagueImpersonationAlert: disclaimerHtml not set and no existing rule to fall back on. Save the standard with the Disclaimer HTML field populated.' -Sev Error
            return
        }
    }

    $BuildRuleStateList = {
        param($Rules)
        foreach ($entry in $groups.GetEnumerator()) {
            $range    = $entry.Key
            $pattern  = $entry.Value
            $ruleName = "($range) Colleague Impersonation Alert"
            $names    = @($displayNames | Where-Object { $_ -match $pattern })
            if ($names.Count -eq 0) { $names = @("($range)") }
            $existing = $Rules | Where-Object { $_.Name -eq $ruleName } | Select-Object -First 1

            $namesMatch    = $false
            $expectedCount = $names.Count
            $actualCount   = 0
            if ($null -ne $existing) {
                $existingPatterns = @($existing.HeaderMatchesPatterns | ForEach-Object { [string]$_ })
                $actualCount      = $existingPatterns.Count
                $namesMatch       = (($names | Sort-Object) -join "`n") -eq (($existingPatterns | Sort-Object) -join "`n")
            }

            [PSCustomObject]@{
                RuleName      = $ruleName
                Range         = $range
                Names         = $names
                ExistingRule  = $existing
                NamesMatch    = $namesMatch
                ExpectedCount = $expectedCount
                ActualCount   = $actualCount
            }
        }
    }

    $ruleStateList = @(& $BuildRuleStateList -Rules $existingRules)

    if ($Settings.remediate -eq $true) {
        foreach ($ruleInfo in $ruleStateList) {
            $ruleName     = $ruleInfo.RuleName
            $range        = $ruleInfo.Range
            $names        = $ruleInfo.Names
            $existingRule = $ruleInfo.ExistingRule

            $seenSenders   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $exemptSenders = [System.Collections.Generic.List[string]]::new()
            foreach ($addr in $additionalExemptSenders) {
                if (-not [string]::IsNullOrWhiteSpace($addr) -and $seenSenders.Add($addr.Trim())) { $exemptSenders.Add($addr.Trim()) }
            }
            foreach ($addr in @($existingRule.ExceptIfFromAddressContainsWords)) {
                $s = [string]$addr
                if (-not [string]::IsNullOrWhiteSpace($s) -and $seenSenders.Add($s.Trim())) { $exemptSenders.Add($s.Trim()) }
            }

            $seenDomains   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $exemptDomains = [System.Collections.Generic.List[string]]::new()
            foreach ($dom in $autoExemptDomains) {
                if (-not [string]::IsNullOrWhiteSpace($dom) -and $seenDomains.Add($dom.Trim())) { $exemptDomains.Add($dom.Trim()) }
            }
            foreach ($dom in @($existingRule.ExceptIfSenderDomainIs)) {
                $s = [string]$dom
                if (-not [string]::IsNullOrWhiteSpace($s) -and $seenDomains.Add($s.Trim())) { $exemptDomains.Add($s.Trim()) }
            }

            $cmdParams = @{
                FromScope                         = 'NotInOrganization'
                ApplyHtmlDisclaimerLocation       = 'Prepend'
                ApplyHtmlDisclaimerFallbackAction = 'Wrap'
                ApplyHtmlDisclaimerText           = $ruleHtml
                ExceptIfSenderDomainIs            = @($exemptDomains)
                HeaderMatchesMessageHeader        = 'From'
                HeaderMatchesPatterns             = $names
                Comments                          = "CIPP managed rule ($range) - Letters $range"
            }
            if ($exemptSenders.Count -gt 0) {
                $cmdParams['ExceptIfFromAddressContainsWords'] = @($exemptSenders)
            }

            if ($null -eq $existingRule) {
                try {
                    $cmdParams['Name'] = $ruleName
                    New-ExoRequest -tenantid $Tenant -cmdlet 'New-TransportRule' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: created rule '$ruleName'." -Sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: failed to create rule '$ruleName'. Error: $ErrorMessage" -Sev Error
                }
            } else {
                try {
                    $cmdParams['Identity'] = $ruleName
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-TransportRule' -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: updated rule '$ruleName'." -Sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: failed to update rule '$ruleName'. Error: $ErrorMessage" -Sev Error
                }
            }
        }

        try {
            $existingRules = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-TransportRule'
            $ruleStateList = @(& $BuildRuleStateList -Rules $existingRules)
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: could not re-fetch transport rules after remediation. Error: $ErrorMessage" -Sev Error
        }
    }

    $missingRules  = @($ruleStateList | Where-Object { $null -eq $_.ExistingRule })
    $staleRules    = @($ruleStateList | Where-Object { $null -ne $_.ExistingRule -and -not $_.NamesMatch })
    $StateIsCorrect = ($missingRules.Count -eq 0) -and ($staleRules.Count -eq 0)

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'ColleagueImpersonationAlert: all 5 transport rules are present and up to date.' -Sev Info
        } else {
            if ($missingRules.Count -gt 0) {
                $missingNames = ($missingRules.RuleName) -join ', '
                Write-StandardsAlert -message "ColleagueImpersonationAlert: missing transport rules: $missingNames" -object @{ MissingRules = $missingNames } -tenant $Tenant -standardName 'ColleagueImpersonationAlert' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: missing transport rules: $missingNames" -Sev Alert
            }
            if ($staleRules.Count -gt 0) {
                $staleDetails = ($staleRules | ForEach-Object { "$($_.RuleName) (expected $($_.ExpectedCount), actual $($_.ActualCount))" }) -join ', '
                Write-StandardsAlert -message "ColleagueImpersonationAlert: stale transport rules (user list out of date): $staleDetails" -object @{ StaleRules = $staleDetails } -tenant $Tenant -standardName 'ColleagueImpersonationAlert' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "ColleagueImpersonationAlert: stale transport rules (user list out of date): $staleDetails" -Sev Alert
            }
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            '(A-E) Colleague Impersonation Alert' = ($null -ne ($ruleStateList | Where-Object { $_.Range -eq 'A-E' } | Select-Object -First 1).ExistingRule) -and (($ruleStateList | Where-Object { $_.Range -eq 'A-E' } | Select-Object -First 1).NamesMatch)
            '(F-J) Colleague Impersonation Alert' = ($null -ne ($ruleStateList | Where-Object { $_.Range -eq 'F-J' } | Select-Object -First 1).ExistingRule) -and (($ruleStateList | Where-Object { $_.Range -eq 'F-J' } | Select-Object -First 1).NamesMatch)
            '(K-O) Colleague Impersonation Alert' = ($null -ne ($ruleStateList | Where-Object { $_.Range -eq 'K-O' } | Select-Object -First 1).ExistingRule) -and (($ruleStateList | Where-Object { $_.Range -eq 'K-O' } | Select-Object -First 1).NamesMatch)
            '(P-T) Colleague Impersonation Alert' = ($null -ne ($ruleStateList | Where-Object { $_.Range -eq 'P-T' } | Select-Object -First 1).ExistingRule) -and (($ruleStateList | Where-Object { $_.Range -eq 'P-T' } | Select-Object -First 1).NamesMatch)
            '(U-Z) Colleague Impersonation Alert' = ($null -ne ($ruleStateList | Where-Object { $_.Range -eq 'U-Z' } | Select-Object -First 1).ExistingRule) -and (($ruleStateList | Where-Object { $_.Range -eq 'U-Z' } | Select-Object -First 1).NamesMatch)
        }
        $ExpectedValue = [PSCustomObject]@{
            '(A-E) Colleague Impersonation Alert' = $true
            '(F-J) Colleague Impersonation Alert' = $true
            '(K-O) Colleague Impersonation Alert' = $true
            '(P-T) Colleague Impersonation Alert' = $true
            '(U-Z) Colleague Impersonation Alert' = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.ColleagueImpersonationAlert' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'ColleagueImpersonationAlert' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
