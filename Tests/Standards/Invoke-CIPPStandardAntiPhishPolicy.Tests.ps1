# Pester tests for Invoke-CIPPStandardAntiPhishPolicy
#
# The select fields arrive as { label, value } objects from the standards form and must reach
# Exchange as their plain value, or New-AntiPhishPolicy rejects the argument transformation.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Modules = Join-Path $RepoRoot 'Modules'
    $StandardPath = Get-ChildItem -Path $Modules -Recurse -Filter 'Invoke-CIPPStandardAntiPhishPolicy.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardAntiPhishPolicy.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, $RequiredCapabilities) $true }
    function Get-CIPPTenantCapabilities { [CmdletBinding()] param($TenantFilter) [pscustomobject]@{ ATP_ENTERPRISE = $true } }
    function New-ExoRequest { [CmdletBinding()] param($cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox, $tenantid, $NoAuthCheck, $Compliance, $ApiVersion, $AvailableCmdlets, $ModuleVersion, $AsApp, $UseCertificate) }
    function ConvertTo-SafeArray { [CmdletBinding()] param($Field) @($Field) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . $StandardPath

    $script:SelectFields = @('AuthenticationFailAction', 'SpoofQuarantineTag', 'MailboxIntelligenceProtectionAction', 'MailboxIntelligenceQuarantineTag', 'TargetedUserProtectionAction', 'TargetedUserQuarantineTag', 'TargetedDomainProtectionAction', 'TargetedDomainQuarantineTag')
}

Describe 'Invoke-CIPPStandardAntiPhishPolicy' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        $script:compare = [System.Collections.Generic.List[object]]::new()
        Mock New-ExoRequest {
            $script:calls.Add([pscustomobject]@{ cmdlet = $cmdlet; cmdParams = $cmdParams })
            if ($cmdlet -eq 'Get-AcceptedDomain') { return [pscustomobject]@{ Name = 'contoso.com' } }
        }
        Mock Set-CIPPStandardsCompareField { $script:compare.Add($ExpectedValue) }
    }

    It 'sends <Shape> select values to Exchange and the compare field as plain strings' -TestCases @(
        @{ Shape = 'label/value object' }
        @{ Shape = 'plain string' }
    ) {
        param($Shape)
        $Settings = [ordered]@{ remediate = $true; report = $true; PhishThresholdLevel = 2 }
        foreach ($Field in $script:SelectFields) {
            $Value = if ($Field -like '*QuarantineTag') { 'AdminOnlyAccessPolicy' } else { 'Quarantine' }
            $Settings[$Field] = if ($Shape -eq 'plain string') { $Value } else { [pscustomobject]@{ label = 'x'; value = $Value } }
        }
        $Settings = $Settings | ConvertTo-Json -Depth 5 | ConvertFrom-Json

        Invoke-CIPPStandardAntiPhishPolicy -Tenant 'contoso.onmicrosoft.com' -Settings $Settings

        $Created = $script:calls.Where({ $_.cmdlet -eq 'New-AntiPhishPolicy' })[0]
        $Created | Should -Not -BeNullOrEmpty
        foreach ($Field in $script:SelectFields) {
            $Created.cmdParams[$Field] | Should -BeOfType [string]
            $script:compare[0].$Field | Should -BeOfType [string]
        }
        $Created.cmdParams.TargetedUserProtectionAction | Should -Be 'Quarantine'
        $Created.cmdParams.SpoofQuarantineTag | Should -Be 'AdminOnlyAccessPolicy'
    }
}
