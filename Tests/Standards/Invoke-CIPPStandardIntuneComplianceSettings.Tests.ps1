# Pester tests for Invoke-CIPPStandardIntuneComplianceSettings
#
# The "Mark devices with no compliance policy as" option stores the strings 'true' / 'false'.
# A [bool] cast reads both as $true, so picking "Compliant" used to report, alert and remediate
# towards Non-Compliant.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardIntuneComplianceSettings.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardIntuneComplianceSettings.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { [CmdletBinding()] param($tenantid, $uri, $type, $body, $AsApp, $ContentType) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardIntuneComplianceSettings secureByDefault' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock New-GraphGetRequest { [PSCustomObject]@{ secureByDefault = $script:TenantValue; deviceComplianceCheckinThresholdDays = 30 } }
        Mock New-GraphPostRequest { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    It 'treats the "Compliant" option (<Shape>) as secureByDefault = false' -ForEach @(
        @{ Shape = 'autoComplete object'; Value = [PSCustomObject]@{ label = 'Compliant'; value = 'false' } }
        @{ Shape = 'plain string'; Value = 'false' }
    ) {
        $script:TenantValue = $false

        Invoke-CIPPStandardIntuneComplianceSettings -Tenant $script:Tenant -Settings @{ secureByDefault = $Value; deviceComplianceCheckinThresholdDays = 30; remediate = $true; alert = $true; report = $true }

        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter { $ExpectedValue.secureByDefault -eq $false }
    }

    It 'remediates a Non-Compliant tenant to false when "Compliant" is chosen' {
        $script:TenantValue = $true

        Invoke-CIPPStandardIntuneComplianceSettings -Tenant $script:Tenant -Settings @{ secureByDefault = [PSCustomObject]@{ value = 'false' }; deviceComplianceCheckinThresholdDays = 30; remediate = $true }

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { ($body | ConvertFrom-Json).settings.secureByDefault -eq $false }
    }

    It 'still treats the "Non-Compliant" option as secureByDefault = true' {
        $script:TenantValue = $true

        Invoke-CIPPStandardIntuneComplianceSettings -Tenant $script:Tenant -Settings @{ secureByDefault = [PSCustomObject]@{ value = 'true' }; deviceComplianceCheckinThresholdDays = 30; remediate = $true; alert = $true }

        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
    }
}
