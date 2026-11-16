# Pester tests for Invoke-CIPPStandardintuneRequireMFA
#
# The standard used to hardcode multiFactorAuthConfiguration = 'required'. It now takes a
# Required / Not required choice; templates saved before that have no state and must keep
# remediating to 'required'.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardintuneRequireMFA.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardintuneRequireMFA.ps1 under Modules/' }

    # Advanced-function stubs: strict binding makes signature drift in the standard fail here.
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid) }
    function New-GraphPostRequest { [CmdletBinding()] param($uri, $tenantid, $body, $type) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardintuneRequireMFA' {
    BeforeEach {
        $script:puts = [System.Collections.Generic.List[object]]::new()
        $script:Current = 'required'

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'deviceRegistrationPolicy'; userDeviceQuota = 50; multiFactorAuthConfiguration = $script:Current }
        }
        Mock -CommandName New-GraphPostRequest -MockWith {
            param($uri, $tenantid, $body, $type)
            $script:puts.Add(($body | ConvertFrom-Json))
        }
    }

    It 'remediates to required when the template has no state saved' {
        $script:Current = 'notRequired'

        Invoke-CIPPStandardintuneRequireMFA -Tenant $script:Tenant -Settings @{ remediate = $true }

        $script:puts.Count | Should -Be 1
        $script:puts[0].multiFactorAuthConfiguration | Should -BeExactly 'required'
    }

    It 'remediates to notRequired and keeps the rest of the policy' {
        $Settings = @{ remediate = $true; state = @{ label = 'Not required'; value = 'notRequired' } }

        Invoke-CIPPStandardintuneRequireMFA -Tenant $script:Tenant -Settings $Settings

        $script:puts.Count | Should -Be 1
        $script:puts[0].multiFactorAuthConfiguration | Should -BeExactly 'notRequired'
        $script:puts[0].userDeviceQuota | Should -Be 50
    }

    It 'does nothing and does not alert when the tenant already matches a bare-string state' {
        $script:Current = 'notRequired'

        Invoke-CIPPStandardintuneRequireMFA -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true; report = $true; state = 'notRequired' }

        $script:puts.Count | Should -Be 0
        Should -Invoke -CommandName Write-StandardsAlert -Times 0 -Exactly
        Should -Invoke -CommandName Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $ExpectedValue.multiFactorAuthConfiguration -eq 'notRequired'
        }
    }

    It 'alerts when the tenant differs from the wanted state' {
        Invoke-CIPPStandardintuneRequireMFA -Tenant $script:Tenant -Settings @{ alert = $true; state = 'notRequired' }

        Should -Invoke -CommandName Write-StandardsAlert -Times 1 -Exactly
    }
}
