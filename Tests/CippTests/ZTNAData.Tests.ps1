BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($Id in '35001', '35003', '35008', '35025', '35026', '35027', '35029', '35030', '35032', '35033', '35041') {
        . (Join-Path $RepoRoot "Modules/CIPPTests/Public/Tests/ZTNA/Identity/Invoke-CippTestZTNA$Id.ps1")
    }

    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields, [switch]$Stream) $script:Data[$Type] }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) if ($script:Data.ContainsKey($Type)) { [pscustomobject]@{ RowKey = "$Type-Count"; DataCount = @($script:Data[$Type]).Count } } }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Test-CIPPStandardLicense {
        param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities, [switch]$SkipLog)
        foreach ($Key in @($Preset) + @($RequiredCapabilities)) { if ($Key -and $script:Licences -contains $Key) { return $true } }
        $false
    }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    function New-CAPolicy($Name, $State, $Include, $Exclude) {
        [pscustomobject]@{ id = $Name; displayName = $Name; state = $State; conditions = [pscustomobject]@{ applications = [pscustomobject]@{ includeApplications = @($Include); excludeApplications = @($Exclude) } }; grantControls = [pscustomobject]@{ builtInControls = @('mfa') }; sessionControls = [pscustomobject]@{ signInFrequency = [pscustomobject]@{ isEnabled = $true }; persistentBrowser = $null } }
    }
    function New-RulePackage($Xml, $Publisher = 'Contoso') { [pscustomobject]@{ RuleCollectionName = 'Pack'; Publisher = $Publisher; ClassificationRuleCollectionXml = $Xml } }
}

Describe 'ZTNA data pillar' {
    BeforeEach {
        $script:Licences = @('Compliance', 'RMS_S_PREMIUM2', 'EXCHANGE_S_ENTERPRISE')
        $script:Data = @{}
        $script:Result = $null
    }

    Describe 'ZTNA35001 Conditional Access RMS exclusion' {
        It 'fails on an enabled policy targeting all apps without excluding RMS' {
            $script:Data['ConditionalAccessPolicies'] = @((New-CAPolicy 'Block' 'enabled' 'All' @()))
            Invoke-CippTestZTNA35001 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '\| mfa \| Sign In Frequency \|'
        }

        It 'passes when RMS is excluded and ignores report-only policies' {
            $script:Data['ConditionalAccessPolicies'] = @(
                (New-CAPolicy 'Excluded' 'enabled' 'All' '00000012-0000-0000-c000-000000000000')
                (New-CAPolicy 'ReportOnly' 'enabledForReportingButNotEnforced' 'All' @())
                (New-CAPolicy 'OtherApp' 'enabled' 'some-app' @())
            )
            Invoke-CippTestZTNA35001 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'passes when the tenant has no Conditional Access policies' {
            $script:Data['ConditionalAccessPolicies'] = @()
            Invoke-CippTestZTNA35001 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
        }

        It 'skips when policies were never collected' {
            Invoke-CippTestZTNA35001 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Skipped'
        }

        It 'reports Unlicensed without RMS_S_PREMIUM2' {
            $script:Licences = @('Compliance')
            Invoke-CippTestZTNA35001 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Unlicensed'
        }
    }

    Describe 'ZTNA35003 sensitivity labels' {
        It 'fails when the collected label set is empty' {
            $script:Data['ExoLabels'] = @()
            Invoke-CippTestZTNA35003 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'skips when labels were never collected' {
            Invoke-CippTestZTNA35003 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Skipped'
        }
    }

    Describe 'ZTNA35008 document library default labels' {
        It 'fails when DisableDocumentLibraryDefaultLabeling is true' {
            $script:Data['SPOTenant'] = @([pscustomobject]@{ DisableDocumentLibraryDefaultLabeling = $true })
            Invoke-CippTestZTNA35008 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }
    }

    Describe 'ZTNA35025 / ZTNA35026 IRM configuration' {
        It 'investigates 35025 when InternalLicensingEnabled is missing' {
            $script:Data['ExoIRMConfiguration'] = @([pscustomobject]@{ AzureRMSLicensingEnabled = $true })
            Invoke-CippTestZTNA35025 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Investigate'
        }

        It 'fails 35025 when internal licensing is disabled' {
            $script:Data['ExoIRMConfiguration'] = @([pscustomobject]@{ InternalLicensingEnabled = $false; AzureRMSLicensingEnabled = $true })
            Invoke-CippTestZTNA35025 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match 'LicensingLocation \| Not configured'
        }

        It 'fails 35026 when Azure RMS is disabled even with simplified client access on' {
            $script:Data['ExoIRMConfiguration'] = @([pscustomobject]@{ AzureRMSLicensingEnabled = $false; SimplifiedClientAccessEnabled = $true })
            Invoke-CippTestZTNA35026 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'investigates 35026 when SimplifiedClientAccessEnabled is missing' {
            $script:Data['ExoIRMConfiguration'] = @([pscustomobject]@{ AzureRMSLicensingEnabled = $true })
            Invoke-CippTestZTNA35026 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Investigate'
        }
    }

    Describe 'ZTNA35027 OME branding' {
        It 'fails when every branding field is blank' {
            $script:Data['ExoOMEConfiguration'] = @([pscustomobject]@{ Identity = 'OME Configuration'; BackgroundColor = ''; ImageUrl = ' ' })
            Invoke-CippTestZTNA35027 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'passes when a logo is configured' {
            $script:Data['ExoOMEConfiguration'] = @([pscustomobject]@{ Identity = 'OME Configuration'; ImageUrl = 'https://logo' })
            Invoke-CippTestZTNA35027 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match '\| OME Configuration \| ❌ None \| ✅ Yes \|'
        }
    }

    Describe 'ZTNA35029 mail flow rights protection' {
        It 'passes on an enabled OME rule and lists rules by priority' {
            $script:Data['ExoTransportRules'] = @(
                [pscustomobject]@{ Name = 'Later'; State = 'Disabled'; Priority = 5; ApplyRightsProtectionTemplate = 'Do Not Forward' }
                [pscustomobject]@{ Name = 'Encrypt'; State = 'Enabled'; Priority = 1; ApplyOME = $true; SentToScope = 'NotInOrganization'; WhenChanged = '2026-01-02T03:04:05Z' }
                [pscustomobject]@{ Name = 'Unrelated'; State = 'Enabled'; Priority = 0; ApplyOME = $false }
            )
            Invoke-CippTestZTNA35029 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match '(?s)\[Encrypt\].*\[Later\]'
            $script:Result.Markdown | Should -Not -Match 'Unrelated'
            $script:Result.Markdown | Should -Match '\| External email protection \| ✅ Yes \|'
        }

        It 'fails when the only protection rule is disabled' {
            $script:Data['ExoTransportRules'] = @([pscustomobject]@{ Name = 'Encrypt'; State = 'Disabled'; Priority = 0; ApplyOME = $true })
            Invoke-CippTestZTNA35029 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
            $script:Result.Markdown | Should -Match '\| Disabled rules \| 1 \|'
        }
    }

    Describe 'ZTNA35030 DLP policies' {
        It 'skips when the tenant has Exchange Online Plan 2 but no Purview licence to collect DLP' {
            $script:Licences = @('EXCHANGE_S_ENTERPRISE')
            Invoke-CippTestZTNA35030 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Skipped'
        }

        It 'fails when every policy is disabled' {
            $script:Data['DlpCompliancePolicies'] = @([pscustomobject]@{ Name = 'Off'; Enabled = $false })
            Invoke-CippTestZTNA35030 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }
    }

    Describe 'ZTNA35032 Adaptive Protection' {
        It 'passes on a rule using SharedByIRMUserRisk and counts its risk levels' {
            $script:Data['DlpComplianceRules'] = @(
                [pscustomobject]@{ Name = 'AP'; ParentPolicyName = 'P1'; Disabled = $false; AdvancedRule = '{"ConditionName":"SharedByIRMUserRisk","Value":["FCB9FA93-6269-4ACF-A756-832E79B36A2A","75A4318B-94A2-4323-BA42-2CA6DB29AAFE"]}' }
                [pscustomobject]@{ Name = 'Plain'; ParentPolicyName = 'P1'; Disabled = $false; AdvancedRule = '{"ConditionName":"ContentContainsSensitiveInformation"}' }
            )
            Invoke-CippTestZTNA35032 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match '\| AP \| P1 \| ✅ Yes \| Elevated, Minor \|'
            $script:Result.Markdown | Should -Match '\| Total DLP Rules \| 2 \|'
        }

        It 'fails when no rules exist' {
            $script:Data['DlpComplianceRules'] = @()
            Invoke-CippTestZTNA35032 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }
    }

    Describe 'ZTNA35033 custom sensitive information types' {
        It 'passes and names the entity from the package localized strings' {
            $Xml = '<?xml version="1.0" encoding="utf-16"?><RulePackage xmlns="http://schemas.microsoft.com/office/2011/mce"><Rules><Entity id="e1"><Pattern /></Entity><LocalizedStrings><Resource idRef="e1"><Name default="true" langcode="en-us">Employee ID</Name><Description default="true" langcode="en-us">Staff numbers</Description></Resource></LocalizedStrings></Rules></RulePackage>'
            $script:Data['ExoDlpSensitiveInfoTypes'] = @(New-RulePackage $Xml)
            Invoke-CippTestZTNA35033 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match '\| Employee ID \| Staff numbers \| Contoso \|'
        }

        It 'fails when the only package defines no entities' {
            $Xml = '<?xml version="1.0" encoding="utf-16"?><RulePackage xmlns="http://schemas.microsoft.com/office/2011/mce"><Rules><Version /><Fingerprint id="f1" /><LocalizedStrings /></Rules></RulePackage>'
            $script:Data['ExoDlpSensitiveInfoTypes'] = @(New-RulePackage $Xml)
            Invoke-CippTestZTNA35033 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }
    }

    Describe 'ZTNA35041 browser DLP' {
        BeforeEach {
            $script:Data['DlpCompliancePolicies'] = @(
                [pscustomobject]@{ Name = 'Browser AI'; Identity = 'id-browser'; Enabled = $true; Mode = 'Enable'; EnforcementPlanes = @('Browser') }
                [pscustomobject]@{ Name = 'Mail'; Identity = 'id-mail'; Enabled = $true; EnforcementPlanes = @('Entra') }
            )
        }

        It 'passes with an enabled Browser policy that has a rule' {
            $script:Data['DlpComplianceRules'] = @([pscustomobject]@{ Name = 'r1'; ParentPolicyName = 'Browser AI' })
            Invoke-CippTestZTNA35041 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Passed'
            $script:Result.Markdown | Should -Match '\| Browser AI \| True \| Enable \| Browser \|.*\| 1 \|'
        }

        It 'fails when the Browser policy has no rules' {
            $script:Data['DlpComplianceRules'] = @([pscustomobject]@{ Name = 'r1'; ParentPolicyName = 'Mail' })
            Invoke-CippTestZTNA35041 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }

        It 'fails when the Browser policy with rules is disabled' {
            $script:Data['DlpCompliancePolicies'][0].Enabled = $false
            $script:Data['DlpComplianceRules'] = @([pscustomobject]@{ Name = 'r1'; Policy = 'id-browser' })
            Invoke-CippTestZTNA35041 -Tenant 'contoso.com'
            $script:Result.Status | Should -Be 'Failed'
        }
    }
}
