# Pester tests for Invoke-CIPPStandardColleagueImpersonationAlert
#
# onmicrosoft domains are filtered off the auto-exempt list, so an onmicrosoft-only tenant ends up with
# no exempt domains. Exchange rejects an empty ExceptIfSenderDomainIs, so it must be left out entirely.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardColleagueImpersonationAlert.ps1')

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $true }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Write-LogMessage { [CmdletBinding()] param($API, $Tenant, $Message, $Sev) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }

    $script:Settings = [PSCustomObject]@{ remediate = $true; disclaimerHtml = '<p>warning</p>' }
}

Describe 'Invoke-CIPPStandardColleagueImpersonationAlert exempt domains' {
    BeforeEach {
        Mock New-ExoRequest { @([PSCustomObject]@{ DisplayName = 'Alice Smith'; AccountDisabled = $false }) } -ParameterFilter { $cmdlet -eq 'Get-Mailbox' }
        Mock New-ExoRequest { @() } -ParameterFilter { $cmdlet -eq 'Get-TransportRule' }
        Mock New-ExoRequest {} -ParameterFilter { $cmdlet -eq 'New-TransportRule' }
    }

    It 'leaves ExceptIfSenderDomainIs out on an onmicrosoft-only tenant' {
        Mock New-ExoRequest { @([PSCustomObject]@{ DomainName = 'contoso.onmicrosoft.com' }) } -ParameterFilter { $cmdlet -eq 'Get-AcceptedDomain' }

        Invoke-CIPPStandardColleagueImpersonationAlert -Tenant 'contoso.onmicrosoft.com' -Settings $script:Settings

        Should -Invoke New-ExoRequest -Times 5 -Exactly -ParameterFilter { $cmdlet -eq 'New-TransportRule' -and -not $cmdParams.ContainsKey('ExceptIfSenderDomainIs') }
    }

    It 'exempts the tenant''s own custom domains' {
        Mock New-ExoRequest { @([PSCustomObject]@{ DomainName = 'contoso.onmicrosoft.com' }, [PSCustomObject]@{ DomainName = 'contoso.com' }) } -ParameterFilter { $cmdlet -eq 'Get-AcceptedDomain' }

        Invoke-CIPPStandardColleagueImpersonationAlert -Tenant 'contoso.com' -Settings $script:Settings

        Should -Invoke New-ExoRequest -Times 5 -Exactly -ParameterFilter { $cmdlet -eq 'New-TransportRule' -and (@($cmdParams.ExceptIfSenderDomainIs) -join ',') -eq 'contoso.com' }
    }
}
