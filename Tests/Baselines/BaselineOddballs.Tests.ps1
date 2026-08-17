# Backlog batch 6: the deferred oddballs. Tests pin the decisions that fail silently - the
# CSS append-never-overwrite rule, the dynamic display-name pattern computation and its
# merge-preserving write, the add-in role containment grade, the storage SP upsert, and the
# Office-by-type detection with the async deploy queue.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp, $ContentType, $AddedHeaders) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = "$Exception"; RawError = '{}' } }
    function ConvertFrom-CippAppConfig { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertFrom-Json } }
    function New-CIPPIntuneAppDeployment { param($AppConfig, $TenantFilter, $APIName) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Get-NormalizedError { param($Message) "$Message" }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Test-CIPPBaselineCacheCollected.ps1')
    foreach ($Name in @('PhishProtection', 'ColleagueImpersonationAlert', 'DisableOutlookAddins',
            'RestrictThirdPartyStorageServices', 'IntuneAppTemplateDeploy')) {
        . (Join-Path $Baselines "Get-CIPPBaseline${Name}State.ps1")
        . (Join-Path $Baselines "Invoke-CIPPBaseline${Name}.ps1")
    }

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 25 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
    Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
}

Describe 'Get-CIPPBaselinePhishProtectionState' {
    BeforeEach {
        Mock Get-Tenants { [PSCustomObject]@{ customerId = 'cust-1' } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ Value = 'cipp.example.com' } }
    }

    It 'grades compliant only when the CSS carries THIS instance''s canary URL' {
        Mock New-GraphGetRequest { ".ext-sign-in-box {`n    background-image: url(https://clone.cipp.app/api/PublicPhishingCheck?Tenantid=$script:Tenant&URL=https://cipp.example.com);`n}`n" }
        $Prepared = Get-CIPPBaselinePhishProtectionState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $Prepared.Current.phishingCSSEnabled | Should -BeTrue
        Mock New-GraphGetRequest { '.other-css { color: red; }' }
        (Get-CIPPBaselinePhishProtectionState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant).Current.phishingCSSEnabled | Should -BeFalse
    }

    It 'APPENDS the canary to the existing custom CSS - operator customizations survive' {
        Mock New-GraphPostRequest { }
        $Current = [PSCustomObject]@{ currentBody = '.operator-css { color: blue; }'; expectedCss = '.canary {}'; customerId = 'cust-1' }
        Invoke-CIPPBaselinePhishProtection -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PUT' -and $body -like '*.operator-css*' -and $body -like '*.canary*'
        }
    }

    It 'strips the malformed empty-URL canary variant before rewriting' {
        Mock New-GraphPostRequest { }
        $Malformed = ".ext-sign-in-box { background-image: url(https://clone.cipp.app/api/PublicPhishingCheck?Tenantid=$script:Tenant&URL=); }"
        $Current = [PSCustomObject]@{ currentBody = $Malformed; expectedCss = '.canary {}'; customerId = 'cust-1' }
        Invoke-CIPPBaselinePhishProtection -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'PUT' -and $body -notlike '*URL=)*' }
    }
}

Describe 'Get-CIPPBaselineColleagueImpersonationAlertState' {
    BeforeAll {
        $script:CachedMailboxes = @(
            @{ displayName = 'Alice Adams'; recipientTypeDetails = 'UserMailbox'; AccountDisabled = $false }
            @{ displayName = 'Frank Field'; recipientTypeDetails = 'UserMailbox'; AccountDisabled = $false }
            @{ displayName = 'Bob Burns (Leaver)'; recipientTypeDetails = 'UserMailbox'; AccountDisabled = $false }
            @{ displayName = 'Carl Closed'; recipientTypeDetails = 'UserMailbox'; AccountDisabled = $true }
            @{ displayName = 'Dana Device'; recipientTypeDetails = 'RoomMailbox'; AccountDisabled = $false }
        )
        $script:CachedDomains = @(@{ DomainName = 'contoso.com' }, @{ DomainName = 'contoso.onmicrosoft.com' })
        $script:MockCaches = {
            param($ExtraRules)
            $script:CachedRules = @($ExtraRules)
            Mock New-CIPPDbRequest {
                switch ($Type) {
                    'Mailboxes' { @($script:CachedMailboxes | ConvertTo-Cached) }
                    'ExoAcceptedDomains' { @($script:CachedDomains | ConvertTo-Cached) }
                    'ExoTransportRules' { @($script:CachedRules | ConvertTo-Cached) }
                }
            }
        }
    }

    It 'computes patterns from ENABLED user/shared mailboxes only - disabled, excluded, and room mailboxes drop out' {
        & $script:MockCaches @()
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ disclaimerHtml = '<b>Warn</b>'; excludedMailboxes = @('(Leaver)') } }
        $Prepared = Get-CIPPBaselineColleagueImpersonationAlertState -Item $Item -TenantFilter $script:Tenant
        $AE = @($Prepared.Current.ruleStates | Where-Object { $_.Range -eq 'A-E' })[0]
        @($AE.Names) | Should -Be @([regex]::Escape('Alice Adams'))
        # The onmicrosoft domain never lands on the exemption list.
        @($Prepared.Current.autoExemptDomains) | Should -Be @('contoso.com')
    }

    It 'the separator adds the short name as a second pattern' {
        $script:CachedMailboxes = @(@{ displayName = 'Alice Adams | Contoso'; recipientTypeDetails = 'UserMailbox'; AccountDisabled = $false })
        & $script:MockCaches @()
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ disclaimerHtml = '<b>W</b>'; displayNameSeparator = '|' } }
        $Prepared = Get-CIPPBaselineColleagueImpersonationAlertState -Item $Item -TenantFilter $script:Tenant
        $AE = @($Prepared.Current.ruleStates | Where-Object { $_.Range -eq 'A-E' })[0]
        @($AE.Names) | Should -Contain ([regex]::Escape('Alice Adams | Contoso'))
        @($AE.Names) | Should -Contain ([regex]::Escape('Alice Adams'))
        $script:CachedMailboxes = @(@{ displayName = 'Alice Adams'; recipientTypeDetails = 'UserMailbox'; AccountDisabled = $false })
    }

    It 'an empty letter group carries its placeholder pattern and a matching rule grades compliant' {
        $Rules = @(foreach ($Range in @('A-E', 'F-J', 'K-O', 'P-T', 'U-Z')) {
                $Patterns = if ($Range -eq 'A-E') { @([regex]::Escape('Alice Adams')) } else { @([regex]::Escape("($Range)")) }
                @{ Name = "($Range) Colleague Impersonation Alert"; HeaderMatchesPatterns = $Patterns; ExceptIfFromAddressContainsWords = @(); ExceptIfSenderDomainIs = @('contoso.com'); ApplyHtmlDisclaimerText = '<b>W</b>' }
            })
        & $script:MockCaches $Rules
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ disclaimerHtml = '<b>W</b>' } }
        $Prepared = Get-CIPPBaselineColleagueImpersonationAlertState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'a missing rule grades that rule as drift, not the whole set' {
        & $script:MockCaches @()
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ disclaimerHtml = '<b>W</b>' } }
        $Prepared = Get-CIPPBaselineColleagueImpersonationAlertState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 5
    }

    It 'the write MERGES existing rule exemptions with the configured ones, deduped case-insensitively' {
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{
            ruleStates              = @([PSCustomObject]@{ RuleName = '(A-E) Colleague Impersonation Alert'; Range = 'A-E'; Names = @('Alice'); RuleExists = $true
                    ExistingExemptSender = @('vip@partner.com', 'SOC@contoso.com'); ExistingExemptDomain = @('legacy.com'); ExistingDisclaimer = '<b>Old</b>' })
            autoExemptDomains       = @('contoso.com', 'LEGACY.com')
            additionalExemptSenders = @('soc@contoso.com')
        }
        Invoke-CIPPBaselineColleagueImpersonationAlert -Remediate ([PSCustomObject]@{ disclaimerHtml = '<b>New</b>' }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-TransportRule' -and
            @($cmdParams.ExceptIfFromAddressContainsWords).Count -eq 2 -and
            $cmdParams.ExceptIfFromAddressContainsWords -contains 'vip@partner.com' -and
            @($cmdParams.ExceptIfSenderDomainIs).Count -eq 2 -and
            $cmdParams.ApplyHtmlDisclaimerText -eq '<b>New</b>'
        }
    }

    It 'OMITS the domain exemption parameter when the list is empty - Exchange rejects an empty one' {
        # onmicrosoft-only tenants have no exemptable accepted domains; passing an empty
        # ExceptIfSenderDomainIs failed every rule write on them.
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{
            ruleStates              = @([PSCustomObject]@{ RuleName = '(A-E) Colleague Impersonation Alert'; Range = 'A-E'; Names = @('Alice'); RuleExists = $false
                    ExistingExemptSender = @(); ExistingExemptDomain = @(); ExistingDisclaimer = '' })
            autoExemptDomains       = @(); additionalExemptSenders = @()
        }
        Invoke-CIPPBaselineColleagueImpersonationAlert -Remediate ([PSCustomObject]@{ disclaimerHtml = '<b>W</b>' }) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'New-TransportRule' -and -not $cmdParams.ContainsKey('ExceptIfSenderDomainIs')
        }
    }

    It 'refuses to write an empty banner: no configured HTML and no fallback throws' {
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{
            ruleStates              = @([PSCustomObject]@{ RuleName = '(A-E) Colleague Impersonation Alert'; Range = 'A-E'; Names = @('Alice'); RuleExists = $false
                    ExistingExemptSender = @(); ExistingExemptDomain = @(); ExistingDisclaimer = '' })
            autoExemptDomains       = @(); additionalExemptSenders = @()
        }
        { Invoke-CIPPBaselineColleagueImpersonationAlert -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current } | Should -Throw
        Should -Invoke New-ExoRequest -Times 0 -Exactly
    }
}

Describe 'Get-CIPPBaselineDisableOutlookAddinsState' {
    It 'any remaining app-install role grades not-disabled' {
        Mock New-ExoRequest { @([PSCustomObject]@{ IsDefault = $true; Identity = 'Default Role Assignment Policy'; AssignedRoles = @('MyBaseOptions', 'My Marketplace Apps') }) }
        $Prepared = Get-CIPPBaselineDisableOutlookAddinsState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $Prepared.Current.disabledOutlookAddins | Should -BeFalse
        @($Prepared.Current.rolesToRemove) | Should -Be @('My Marketplace Apps')
    }

    It 'removes each role''s assignments by GUID and throws only when EVERY role fails' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Get-ManagementRoleAssignment') { @([PSCustomObject]@{ Guid = 'guid-1' }) }
            elseif ($cmdlet -eq 'Remove-ManagementRoleAssignment' -and $cmdParams.Identity -eq 'guid-1') { }
        }
        $Current = [PSCustomObject]@{ policyIdentity = 'Default Role Assignment Policy'; rolesToRemove = @('My Custom Apps', 'My Marketplace Apps') }
        Invoke-CIPPBaselineDisableOutlookAddins -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 2 -Exactly -ParameterFilter { $cmdlet -eq 'Remove-ManagementRoleAssignment' }
        Mock New-ExoRequest { throw 'denied' }
        { Invoke-CIPPBaselineDisableOutlookAddins -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current } | Should -Throw
    }
}

Describe 'Get-CIPPBaselineRestrictThirdPartyStorageServicesState' {
    It 'a MISSING service principal grades unrestricted - the platform default is enabled' {
        Mock New-CIPPDbRequest { @(@{ appId = 'other'; accountEnabled = $true } | ConvertTo-Cached) }
        (Get-CIPPBaselineRestrictThirdPartyStorageServicesState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant).Current.thirdPartyStorageRestricted | Should -BeFalse
    }

    It 'a disabled service principal grades restricted' {
        Mock New-CIPPDbRequest { @(@{ appId = 'c1f33bc0-bdb4-4248-ba9b-096807ddb43e'; accountEnabled = $false } | ConvertTo-Cached) }
        (Get-CIPPBaselineRestrictThirdPartyStorageServicesState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant).Current.thirdPartyStorageRestricted | Should -BeTrue
    }

    It 'the write is the appId-addressed upsert carrying Prefer: create-if-missing' {
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineRestrictThirdPartyStorageServices -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $uri -like "*servicePrincipals(appId='c1f33bc0*" -and
            $AddedHeaders.Prefer -eq 'create-if-missing' -and ($body | ConvertFrom-Json).accountEnabled -eq $false
        }
    }
}

Describe 'Get-CIPPBaselineDlpCompliancePolicyTemplateState' {
    BeforeAll {
        function Compare-CIPPDlpCompliancePolicy { param($TenantFilter, $Template) }
        function Set-CIPPDlpCompliancePolicy { param($TenantFilter, $Template, $APIName) }
        function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineDlpCompliancePolicyTemplateState.ps1')
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineDlpCompliancePolicyTemplate.ps1')
        $script:DlpItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ dlpCompliancePolicyTemplate = [PSCustomObject]@{ value = 'dlp-guid-1' } } }
    }
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ JSON = '{"Name":"Finance DLP","RuleParams":[{"Name":"Rule1"}]}' } }
    }

    It 'InSync grades compliant with an empty non-compliant list' {
        Mock Compare-CIPPDlpCompliancePolicy { [PSCustomObject]@{ Name = 'Finance DLP'; State = 'InSync'; Differences = @() } }
        $Prepared = Get-CIPPBaselineDlpCompliancePolicyTemplateState -Item $script:DlpItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'Drift grades non-compliant with the compact Scope/Field projection and carries the template' {
        Mock Compare-CIPPDlpCompliancePolicy { [PSCustomObject]@{ Name = 'Finance DLP'; State = 'Drift'; Differences = @(
                    [PSCustomObject]@{ Scope = 'Policy'; Field = 'Mode'; Expected = 'Enable'; Current = 'TestWithoutNotifications' }
                ) } }
        $Prepared = Get-CIPPBaselineDlpCompliancePolicyTemplateState -Item $script:DlpItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
        @($Prepared.Current.nonCompliantDlpPolicies)[0].Fields | Should -Be @('Policy/Mode')
        @($Prepared.Current.remediableTemplates).Count | Should -Be 1
    }

    It 'PendingDeletion is non-compliant but NOT remediable - the deploy would just fail' {
        Mock Compare-CIPPDlpCompliancePolicy { [PSCustomObject]@{ Name = 'Finance DLP'; State = 'PendingDeletion'; Differences = @() } }
        $Prepared = Get-CIPPBaselineDlpCompliancePolicyTemplateState -Item $script:DlpItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
        @($Prepared.Current.remediableTemplates).Count | Should -Be 0
        Mock Set-CIPPDlpCompliancePolicy { 'should never run' }
        Invoke-CIPPBaselineDlpCompliancePolicyTemplate -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Prepared.Current
        Should -Invoke Set-CIPPDlpCompliancePolicy -Times 0 -Exactly
    }

    It 'the executor throws on the helper''s failure strings and succeeds otherwise' {
        Mock Set-CIPPDlpCompliancePolicy { 'Could not deploy Finance DLP: bad rule' }
        $Current = [PSCustomObject]@{ remediableTemplates = @([PSCustomObject]@{ Name = 'Finance DLP' }) }
        { Invoke-CIPPBaselineDlpCompliancePolicyTemplate -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current } | Should -Throw
        Mock Set-CIPPDlpCompliancePolicy { 'Deployed policy Finance DLP with 1 rule(s)' }
        { Invoke-CIPPBaselineDlpCompliancePolicyTemplate -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current } | Should -Not -Throw
    }
}

Describe 'Get-CIPPBaselineIntuneAppTemplateDeployState' {
    BeforeAll {
        $script:AppTemplate = @{ JSON = (@{ Displayname = 'Baseline Apps'; Apps = @(
                    @{ appType = 'StoreApp'; appName = '7zip'; config = @{ ApplicationName = '7-Zip'; AssignTo = 'AllDevices' } }
                    @{ appType = 'officeApp'; appName = 'M365 Apps'; config = @{ ApplicationName = 'Office' } }
                ) } | ConvertTo-Json -Depth 10) }
    }

    It 'Office is tracked by @odata.type - Graph renames it, the template name never matches' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ JSON = $script:AppTemplate.JSON } }
        Mock New-CIPPDbRequest { @(
                (@{ displayName = '7-Zip'; '@odata.type' = '#microsoft.graph.win32LobApp' } | ConvertTo-Cached)
                (@{ displayName = 'Microsoft 365 Apps for Windows 10 and later'; '@odata.type' = '#microsoft.graph.officeSuiteApp' } | ConvertTo-Cached)
            ) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ templateIds = @([PSCustomObject]@{ value = 't-1' }) } }
        $Prepared = Get-CIPPBaselineIntuneAppTemplateDeployState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'a missing app grades drift and carries its full deploy config for the executor' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ JSON = $script:AppTemplate.JSON } }
        Mock New-CIPPDbRequest { @((@{ displayName = 'Microsoft 365 Apps for Windows 10 and later'; '@odata.type' = '#microsoft.graph.officeSuiteApp' } | ConvertTo-Cached)) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ templateIds = @('t-1') } }
        $Prepared = Get-CIPPBaselineIntuneAppTemplateDeployState -Item $Item -TenantFilter $script:Tenant
        @($Prepared.Current.missingApps) | Should -Be @('7-Zip')
        @($Prepared.Current.missingAppObjects)[0].AppType | Should -Be 'StoreApp'
    }

    It 'the executor maps template types to queue types and continues past per-app failures' {
        Mock New-CIPPIntuneAppDeployment { if ($AppConfig.Applicationname -eq 'BadApp') { throw 'upload refused' } }
        $Current = [PSCustomObject]@{ missingAppObjects = @(
                [PSCustomObject]@{ TemplateId = 't-1'; TemplateName = 'T'; AppName = 'BadApp'; AppType = 'chocolateyApp'; Config = [PSCustomObject]@{ AssignTo = 'AllDevices' } }
                [PSCustomObject]@{ TemplateId = 't-1'; TemplateName = 'T'; AppName = '7-Zip'; AppType = 'StoreApp'; Config = [PSCustomObject]@{ AssignTo = 'customGroup'; CustomGroup = 'Pilot Group' } }
            ) }
        Invoke-CIPPBaselineIntuneAppTemplateDeploy -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-CIPPIntuneAppDeployment -Times 2 -Exactly
        Should -Invoke New-CIPPIntuneAppDeployment -Times 1 -Exactly -ParameterFilter {
            $AppConfig.type -eq 'WinGet' -and $AppConfig.assignTo -eq 'Pilot Group'
        }
    }
}
