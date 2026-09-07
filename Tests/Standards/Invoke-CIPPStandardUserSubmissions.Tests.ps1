# Pester tests for Invoke-CIPPStandardUserSubmissions.
#
# The comparison payload contains two related but distinct states:
# EnableReportToMicrosoft controls the built-in Outlook Report button, while
# CustomDestinationRule describes the optional rule that sends submissions to a custom address.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardUserSubmissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardUserSubmissions.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField {
        [CmdletBinding()]
        param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter)
    }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardUserSubmissions comparison payload' {
    BeforeEach {
        $script:compareFields = [System.Collections.Generic.List[object]]::new()
        $script:policyState = [pscustomobject]@{
            EnableReportToMicrosoft          = $true
            ReportJunkToCustomizedAddress    = $false
            ReportNotJunkToCustomizedAddress = $false
            ReportPhishToCustomizedAddress   = $false
            ReportJunkAddresses              = @()
            ReportNotJunkAddresses           = @()
            ReportPhishAddresses             = @()
        }
        $script:ruleState = @()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { param($TenantFilter, $Text) $Text }
        Mock -CommandName New-ExoRequest -MockWith {
            param($tenantid, $cmdlet, $cmdParams)
            if ($cmdlet -eq 'Get-ReportSubmissionPolicy') { return $script:policyState }
            if ($cmdlet -eq 'Get-ReportSubmissionRule') { return $script:ruleState }
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter)
            $script:compareFields.Add([pscustomobject]@{
                    Field    = $FieldName
                    Current  = $CurrentValue
                    Expected = $ExpectedValue
                    Tenant   = $TenantFilter
                })
        }
    }

    It 'shows built-in reporting enabled and the custom rule disabled when no email is configured' {
        $script:ruleState = @(
            [pscustomobject]@{
                State  = 'Enabled'
                SentTo = 'old-destination@contoso.com'
            }
        )

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{
            state  = 'enable'
            email  = $null
            report = $true
        }

        $Comparison = $script:compareFields[0]
        $Comparison.Expected.EnableReportToMicrosoft | Should -BeTrue
        $Comparison.Expected.CustomDestinationRule.State | Should -Be 'Disabled'
        $Comparison.Expected.CustomDestinationRule.SentTo | Should -BeNullOrEmpty
        $Comparison.Current.CustomDestinationRule.State | Should -Be 'Enabled'
        $Comparison.Current.CustomDestinationRule.SentTo | Should -Be 'old-destination@contoso.com'
        $Comparison.Expected.PSObject.Properties.Name | Should -Not -Contain 'RuleState'
        $Comparison.Current.PSObject.Properties.Name | Should -Not -Contain 'RuleState'
    }

    It 'shows the enabled custom destination rule when an email is configured' {
        $Email = 'security@contoso.com'
        $script:policyState = [pscustomobject]@{
            EnableReportToMicrosoft          = $true
            ReportJunkToCustomizedAddress    = $true
            ReportNotJunkToCustomizedAddress = $true
            ReportPhishToCustomizedAddress   = $true
            ReportJunkAddresses              = $Email
            ReportNotJunkAddresses           = $Email
            ReportPhishAddresses             = $Email
        }
        $script:ruleState = [pscustomobject]@{
            State  = 'Enabled'
            SentTo = $Email
        }

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{
            state  = 'enable'
            email  = $Email
            report = $true
        }

        $Comparison = $script:compareFields[0]
        $Comparison.Expected.EnableReportToMicrosoft | Should -BeTrue
        $Comparison.Expected.CustomDestinationRule.State | Should -Be 'Enabled'
        $Comparison.Expected.CustomDestinationRule.SentTo | Should -Be $Email
        $Comparison.Current.CustomDestinationRule.State | Should -Be 'Enabled'
        $Comparison.Current.CustomDestinationRule.SentTo | Should -Be $Email
    }

    It 'expects reporting to Microsoft OFF when the destination is the reporting mailbox only' {
        $Email = 'phish@contoso.com'
        $script:policyState = [pscustomobject]@{
            EnableReportToMicrosoft          = $false
            ReportJunkToCustomizedAddress    = $true
            ReportNotJunkToCustomizedAddress = $true
            ReportPhishToCustomizedAddress   = $true
            ReportJunkAddresses              = $Email
            ReportNotJunkAddresses           = $Email
            ReportPhishAddresses             = $Email
        }
        $script:ruleState = [pscustomobject]@{
            State  = 'Enabled'
            SentTo = $Email
        }

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{
            state             = 'enable'
            email             = $Email
            reportDestination = 'Mailbox'
            report            = $true
        }

        $Comparison = $script:compareFields[0]
        $Comparison.Expected.EnableReportToMicrosoft | Should -BeFalse
        $Comparison.Expected.CustomDestinationRule.State | Should -Be 'Enabled'
        $Comparison.Expected.CustomDestinationRule.SentTo | Should -Be $Email
        $Comparison.Current.EnableReportToMicrosoft | Should -BeFalse
    }

    It 'remediates to the reporting mailbox only without re-enabling reporting to Microsoft' {
        # The exact regression from issue #409: a tenant set to 'My reporting mailbox only'
        # must not be flipped back to reporting to Microsoft by the standard.
        $Email = 'phish@contoso.com'
        $script:ruleState = @()

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{
            state             = 'enable'
            email             = $Email
            reportDestination = 'Mailbox'
            remediate         = $true
        }

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-ReportSubmissionPolicy' -and
            $cmdParams.EnableReportToMicrosoft -eq $false -and
            $cmdParams.ReportPhishToCustomizedAddress -eq $true -and
            $cmdParams.ReportPhishAddresses -eq $Email
        }
    }

    It 'still remediates to Microsoft and the reporting mailbox when no destination is chosen' {
        $Email = 'phish@contoso.com'
        $script:ruleState = @()

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{
            state     = 'enable'
            email     = $Email
            remediate = $true
        }

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-ReportSubmissionPolicy' -and
            $cmdParams.EnableReportToMicrosoft -eq $true -and
            $cmdParams.ReportPhishAddresses -eq $Email
        }
    }

    It 'shows both reporting and the custom destination rule disabled when the standard is disabled' {
        $script:policyState = [pscustomobject]@{
            EnableReportToMicrosoft          = $false
            ReportJunkToCustomizedAddress    = $false
            ReportNotJunkToCustomizedAddress = $false
            ReportPhishToCustomizedAddress   = $false
            ReportJunkAddresses              = @()
            ReportNotJunkAddresses           = @()
            ReportPhishAddresses             = @()
        }

        Invoke-CIPPStandardUserSubmissions -Tenant $script:Tenant -Settings @{
            state  = 'disable'
            email  = $null
            report = $true
        }

        $Comparison = $script:compareFields[0]
        $Comparison.Expected.EnableReportToMicrosoft | Should -BeFalse
        $Comparison.Expected.CustomDestinationRule.State | Should -Be 'Disabled'
        $Comparison.Expected.CustomDestinationRule.SentTo | Should -BeNullOrEmpty
        $Comparison.Current.EnableReportToMicrosoft | Should -BeFalse
        $Comparison.Current.CustomDestinationRule.State | Should -Be 'Disabled'
    }
}
