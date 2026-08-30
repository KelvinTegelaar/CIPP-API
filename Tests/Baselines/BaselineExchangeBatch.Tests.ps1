# Backlog batch 2: the Exchange cluster. Tests pin the normalization and grading decisions
# that fail silently - wrong-shaped duration compares, per-language contains semantics,
# additive-vs-strict list ownership, and the link write that must never unlink other tags.
# Also hosts the TeamsFederation single-domain array-shape regression.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox, $ReturnWithCommand) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Get-NormalizedError { param($Message) "$Message" }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Test-CIPPBaselineCacheCollected.ps1')
    foreach ($Name in @('GlobalQuarantineSettings', 'GlobalQuarantineNotifications', 'UserSubmissions', 'RetentionPolicyTag',
            'SendReceiveLimitTenant', 'AddDKIM', 'RotateDKIM', 'PhishSimSpoofIntelligence', 'PhishingSimulations')) {
        . (Join-Path $Baselines "Get-CIPPBaseline${Name}State.ps1")
        . (Join-Path $Baselines "Invoke-CIPPBaseline${Name}.ps1")
    }

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
    Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
}

Describe 'Get-CIPPBaselineGlobalQuarantineSettingsState' {
    BeforeAll {
        $script:GqPolicy = @{ Name = 'DefaultGlobalTag'; Identity = 'DefaultGlobalTag'; MultiLanguageSetting = @('Default', 'Dutch')
            MultiLanguageSenderName = @('IT Alerts', 'IT Meldingen'); ESNCustomSubject = @('Quarantined mail', 'Bericht in quarantaine')
            MultiLanguageCustomDisclaimer = @(); EndUserSpamNotificationCustomFromAddress = 'alerts@contoso.com'; OrganizationBrandingEnabled = $true }
    }

    It 'grades a per-language text as contains: present in ANY language slot is compliant' {
        # The configured value sits in the SECOND language slot on purpose - a first-slot
        # equality compare would miss it and report drift the write cannot clear.
        Mock New-CIPPDbRequest { @($script:GqPolicy | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ SenderName = 'IT Meldingen'; OrganizationBrandingEnabled = $true } }
        $Prepared = Get-CIPPBaselineGlobalQuarantineSettingsState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'does not grade fields the baseline leaves empty - the classic graded them as permanent drift' {
        Mock New-CIPPDbRequest { @($script:GqPolicy | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ OrganizationBrandingEnabled = $true } }
        $Prepared = Get-CIPPBaselineGlobalQuarantineSettingsState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'senderNamePresent'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'sends ALL THREE per-language arrays at equal counts, preserving unconfigured values' {
        # Exchange rejects the write outright unless sender, subject and disclaimer arrays
        # all match the language count - and the unconfigured subject must resend the
        # tenant's existing values, not blanks.
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{
            languages = @('Default', 'Dutch'); policyName = 'DefaultGlobalTag'; policyIdentity = 'DefaultGlobalTag'
            currentSenderNames = @('Old', 'Oud'); currentSubjects = @('Quarantined mail', 'Bericht in quarantaine'); currentDisclaimers = @()
        }
        Invoke-CIPPBaselineGlobalQuarantineSettings -Remediate ([PSCustomObject]@{ senderName = 'IT Alerts'; organizationBrandingEnabled = $true }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-QuarantinePolicy' -and
            @($cmdParams.MultiLanguageSenderName).Count -eq 2 -and $cmdParams.MultiLanguageSenderName[0] -eq 'IT Alerts' -and
            @($cmdParams.ESNCustomSubject).Count -eq 2 -and $cmdParams.ESNCustomSubject[1] -eq 'Bericht in quarantaine' -and
            @($cmdParams.MultiLanguageCustomDisclaimer).Count -eq 2
        }
    }

    It 'creates the custom global policy when the tenant still runs the Microsoft default' {
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{ languages = @('Default'); policyName = 'DefaultGlobalPolicy'; policyIdentity = 'DefaultGlobalPolicy'; currentSenderNames = @(); currentSubjects = @(); currentDisclaimers = @() }
        Invoke-CIPPBaselineGlobalQuarantineSettings -Remediate ([PSCustomObject]@{ organizationBrandingEnabled = $false }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-QuarantinePolicy' -and $cmdParams.Name -eq 'DefaultGlobalTag' }
    }
}

Describe 'Get-CIPPBaselineGlobalQuarantineNotificationsState' {
    It 'normalizes the ISO duration and the timespan string to the same hours' {
        Mock New-CIPPDbRequest { @(@{ Name = 'DefaultGlobalTag'; Identity = 'x'; EndUserSpamNotificationFrequency = 'P1D' } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ NotificationInterval = '1.00:00:00' } }
        $Prepared = Get-CIPPBaselineGlobalQuarantineNotificationsState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'grades an unrecognized tenant interval as drift, never as compliant' {
        Mock New-CIPPDbRequest { @(@{ Name = 'DefaultGlobalTag'; Identity = 'x'; EndUserSpamNotificationFrequency = 'PT15M' } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ NotificationInterval = '04:00:00' } }
        $Prepared = Get-CIPPBaselineGlobalQuarantineNotificationsState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-CIPPBaselineUserSubmissionsState' {
    It 'requires ALL THREE report types at the custom address, not just one' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'ReportSubmissionPolicy') { @(@{ EnableReportToMicrosoft = $true; ReportJunkToCustomizedAddress = $true; ReportJunkAddresses = @('soc@contoso.com'); ReportNotJunkToCustomizedAddress = $false; ReportNotJunkAddresses = @(); ReportPhishToCustomizedAddress = $true; ReportPhishAddresses = @('soc@contoso.com') } | ConvertTo-Cached) }
            else { @(@{ State = 'Enabled'; SentTo = @('soc@contoso.com') } | ConvertTo-Cached) }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = 'enable'; email = 'soc@contoso.com' } }
        $Prepared = Get-CIPPBaselineUserSubmissionsState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.customAddressCorrect | Should -BeFalse
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'treats no policy at all as compliant for the disable posture' {
        Mock New-CIPPDbRequest { @() }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ state = 'disable' } }
        $Prepared = Get-CIPPBaselineUserSubmissionsState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'removes an enabled rule when turning reporting off, and only then' {
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{ policyExists = $true; ruleExists = $true; ruleEnabled = $true; resolvedEmail = '' }
        Invoke-CIPPBaselineUserSubmissions -Remediate ([PSCustomObject]@{ state = 'disable' }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Remove-ReportSubmissionRule' }
    }
}

Describe 'Get-CIPPBaselineRetentionPolicyTagState' {
    BeforeAll {
        $script:GoodTag = @{ Identity = 'CIPP Deleted Items'; Name = 'CIPP Deleted Items'; RetentionEnabled = $true; RetentionAction = 'PermanentlyDelete'; AgeLimitForRetention = '30.00:00:00'; Type = 'DeletedItems' }
    }

    It 'grades the MRM policy link separately - an unlinked tag does nothing' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'ExoRetentionPolicyTags') { @($script:GoodTag | ConvertTo-Cached) }
            else { @(@{ Identity = 'Default MRM Policy'; RetentionPolicyTagLinks = @('Junk Email', '1 Month Delete') } | ConvertTo-Cached) }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ AgeLimitForRetention = 30 } }
        $Prepared = Get-CIPPBaselineRetentionPolicyTagState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.linkedToPolicy | Should -BeFalse
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'resends the FULL link list plus ours - sending only the new tag unlinks everything else' {
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{ tagExists = $true; linkedToPolicy = $false; existingLinks = @('Junk Email', '1 Month Delete') }
        Invoke-CIPPBaselineRetentionPolicyTag -Remediate ([PSCustomObject]@{ ageLimitForRetention = 30 }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-RetentionPolicy' -and @($cmdParams.RetentionPolicyTagLinks).Count -eq 3 -and $cmdParams.RetentionPolicyTagLinks -contains 'Junk Email'
        }
    }
}

Describe 'Get-CIPPBaselineSendReceiveLimitTenantState' {
    It 'parses the display-string byte counts and treats Unlimited as an offender' {
        Mock New-CIPPDbRequest { @(
                (@{ DisplayName = 'ExchangeOnlineEnterprise'; MaxSendSize = '35 MB (36,700,160 bytes)'; MaxReceiveSize = '36 MB (37,748,736 bytes)'; Guid = 'g1' } | ConvertTo-Cached),
                (@{ DisplayName = 'ExchangeOnlineDeskless'; MaxSendSize = 'Unlimited'; MaxReceiveSize = '36 MB (37,748,736 bytes)'; Guid = 'g2' } | ConvertTo-Cached)
            ) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ SendLimit = 35; ReceiveLimit = 36 } }
        $Prepared = Get-CIPPBaselineSendReceiveLimitTenantState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.plansOffLimits | Should -Be @('ExchangeOnlineDeskless')
        $Prepared.Current.offenderGuids | Should -Be @('g2')
    }
}

Describe 'Get-CIPPBaselineAddDKIMState' {
    It 'excludes service domains and splits create-vs-enable for the executor' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'ExoAcceptedDomains') { @(
                    (@{ DomainName = 'contoso.com' } | ConvertTo-Cached),
                    (@{ DomainName = 'contoso.mail.onmicrosoft.com' } | ConvertTo-Cached),
                    (@{ DomainName = 'fabrikam.com' } | ConvertTo-Cached)
                ) }
            else { @(@{ Domain = 'fabrikam.com'; Enabled = $false } | ConvertTo-Cached) }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{} }
        $Prepared = Get-CIPPBaselineAddDKIMState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.domainsToCreate | Should -Be @('contoso.com')
        $Prepared.Current.domainsToEnable | Should -Be @('fabrikam.com')
        $Prepared.Current.domainsWithoutDkim | Should -Not -Contain 'contoso.mail.onmicrosoft.com'
    }
}

Describe 'Get-CIPPBaselineRotateDKIMState' {
    It 'grades only ENABLED configs on 1024-bit keys - rotating a disabled config does nothing' {
        Mock New-CIPPDbRequest { @(
                (@{ Identity = 'contoso.com'; Selector1KeySize = 1024; Selector2KeySize = 2048; Enabled = $true } | ConvertTo-Cached),
                (@{ Identity = 'fabrikam.com'; Selector1KeySize = 1024; Selector2KeySize = 1024; Enabled = $false } | ConvertTo-Cached),
                (@{ Identity = 'tailspin.com'; Selector1KeySize = 2048; Selector2KeySize = 2048; Enabled = $true } | ConvertTo-Cached)
            ) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{} }
        (Get-CIPPBaselineRotateDKIMState -Item $Item -TenantFilter $script:Tenant).Current.domainsWith1024BitDkim | Should -Be @('contoso.com')
    }
}

Describe 'Get-CIPPBaselinePhishSimSpoofIntelligenceState' {
    It 'is additive by default: hand-added spoof allowances are not drift' {
        Mock New-CIPPDbRequest { @(
                (@{ Identity = 'id1'; SendingInfrastructure = 'sim.knowbe4.com' } | ConvertTo-Cached),
                (@{ Identity = 'id2'; SendingInfrastructure = 'operator-added.example' } | ConvertTo-Cached)
            ) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ AllowedDomains = @('sim.knowbe4.com'); RemoveExtraDomains = $false } }
        $Prepared = Get-CIPPBaselinePhishSimSpoofIntelligenceState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'strict mode grades extras and carries their item ids for removal' {
        Mock New-CIPPDbRequest { @(@{ Identity = 'id2'; SendingInfrastructure = 'operator-added.example' } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ AllowedDomains = @('sim.knowbe4.com'); RemoveExtraDomains = $true } }
        $Prepared = Get-CIPPBaselinePhishSimSpoofIntelligenceState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.extraDomains | Should -Contain 'operator-added.example'
        $Prepared.Current.extraItemIds | Should -Be @('id2')
    }

    It 'writes each missing domain as BOTH Internal and External spoof types' {
        Mock New-ExoBulkRequest { @() }
        $Current = [PSCustomObject]@{ missingDomains = @('sim.knowbe4.com'); extraItemIds = @() }
        Invoke-CIPPBaselinePhishSimSpoofIntelligence -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
            @($cmdletArray).Count -eq 2 -and @($cmdletArray.CmdletInput.Parameters.SpoofType) -contains 'Internal' -and @($cmdletArray.CmdletInput.Parameters.SpoofType) -contains 'External'
        }
    }
}

Describe 'Get-CIPPBaselinePhishingSimulationsState' {
    BeforeAll {
        $script:PsItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{
                Domains = @('sim.example.com'); SenderIpRanges = @('10.1.1.0/24'); PhishingSimUrls = @('https://sim.example.com/*'); RemoveExtraUrls = $false } }
    }

    It 'grades the three legs separately so the drift row names the broken one' {
        Mock New-CIPPDbRequest {
            switch ($Type) {
                'ExoPhishSimOverridePolicy' { @(@{ Name = 'PhishSimOverridePolicy'; Enabled = $true } | ConvertTo-Cached) }
                'ExoPhishSimOverrideRule' { @(@{ Name = 'PhishSimOverrideRule'; Identity = 'r1'; SenderIpRanges = @('10.1.1.0/24'); Domains = @() } | ConvertTo-Cached) }
                default { @(@{ Value = 'https://sim.example.com/*' } | ConvertTo-Cached) }
            }
        }
        $Prepared = Get-CIPPBaselinePhishingSimulationsState -Item $script:PsItem -TenantFilter $script:Tenant
        $Prepared.Current.policyEnabled | Should -BeTrue
        $Prepared.Current.missingDomains | Should -Be @('sim.example.com')
        @($Prepared.Current.missingUrls).Count | Should -Be 0
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'uses add/remove DELTAS on an existing rule, never replacement lists' {
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{
            policyEnabled = $true; policyExists = $true; ruleExists = $true; ruleIdentity = 'r1'
            missingDomains = @('sim.example.com'); missingSenderIpRanges = @(); extraDomains = @('old.example.com'); extraSenderIpRanges = @()
            missingUrls = @(); extraUrls = @()
        }
        Invoke-CIPPBaselinePhishingSimulations -Remediate ([PSCustomObject]@{ domains = @('sim.example.com'); senderIpRanges = @('10.1.1.0/24') }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-ExoPhishSimOverrideRule' -and $cmdParams.AddDomains -contains 'sim.example.com' -and $cmdParams.RemoveDomains -contains 'old.example.com'
        }
    }
}

Describe 'Get-CIPPBaselineSpamFilterPolicyState block-list write params' {
    BeforeAll {
        . (Join-Path (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines') 'Get-CIPPBaselineSpamFilterPolicyState.ps1')
        $script:SpamPolicy = @{ Name = 'CIPP Default Spam Filter Policy'; EnableRegionBlockList = $true; EnableLanguageBlockList = $false }
        $script:SpamRule = @{ Name = 'CIPP Default Spam Filter Policy'; State = 'Enabled'; Priority = 0; HostedContentFilterPolicy = 'CIPP Default Spam Filter Policy'; RecipientDomainIs = @('contoso.com') }
    }
    BeforeEach {
        Mock New-CIPPDbRequest {
            switch ($Type) {
                'ExoHostedContentFilterPolicy' { @($script:SpamPolicy | ConvertTo-Cached) }
                'ExoHostedContentFilterRule' { @($script:SpamRule | ConvertTo-Cached) }
                'ExoAcceptedDomains' { @(@{ Name = 'contoso.com' } | ConvertTo-Cached) }
            }
        }
    }

    It 'forces the block-list switches OFF in the write when disabled - omitting them left a tenant-side On in place forever' {
        # The classic explicitly wrote EnableRegionBlockList=$false when disabled; the
        # rendered spec omitted it, so grade said Off while the tenant stayed On (proven
        # live: enableRegionBlockList exp=false got=true after a clean remediation).
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ EnableRegionBlockList = $false } }
        $Prepared = Get-CIPPBaselineSpamFilterPolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.extraPolicyParams.PSObject.Properties.Name | Should -Contain 'EnableRegionBlockList'
        $Prepared.Current.extraPolicyParams.PSObject.Properties.Name | Should -Contain 'EnableLanguageBlockList'
        $Prepared.Current.extraPolicyParams.EnableRegionBlockList | Should -BeFalse
        $Prepared.Current.extraPolicyParams.EnableLanguageBlockList | Should -BeFalse
        $Prepared.Current.extraPolicyParams.PSObject.Properties.Name | Should -Not -Contain 'RegionBlockList'
        $Prepared.Expected.enableRegionBlockList | Should -BeFalse
    }

    It 'writes the switch AND the normalized list when enabled with entries, exactly as graded' {
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ EnableRegionBlockList = $true; RegionBlockList = @('ru', 'kp') } }
        $Prepared = Get-CIPPBaselineSpamFilterPolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Current.extraPolicyParams.EnableRegionBlockList | Should -BeTrue
        @($Prepared.Current.extraPolicyParams.RegionBlockList) | Should -BeExactly @('KP', 'RU')
        $Prepared.Expected.enableRegionBlockList | Should -BeTrue
    }

    It 'never grades or writes BulkMovesEnabled unless explicitly configured - the parameter is in Preview and not available in every organization' {
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ } }
        $Prepared = Get-CIPPBaselineSpamFilterPolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Not -Contain 'bulkMovesEnabled'
        $Prepared.Current.extraPolicyParams.PSObject.Properties.Name | Should -Not -Contain 'BulkMovesEnabled'
    }

    It 'grades and writes BulkMovesEnabled when configured On, unwrapping an option wrapper if the picker saved one' {
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ BulkMovesEnabled = [PSCustomObject]@{ label = 'On'; value = 'On' } } }
        $Prepared = Get-CIPPBaselineSpamFilterPolicyState -Item $Item -TenantFilter $script:Tenant
        $Prepared.Expected.bulkMovesEnabled | Should -BeExactly 'On'
        $Prepared.Current.extraPolicyParams.BulkMovesEnabled | Should -BeExactly 'On'
    }
}
