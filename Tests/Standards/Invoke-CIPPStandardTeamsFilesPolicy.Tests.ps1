# Pester tests for Invoke-CIPPStandardTeamsFilesPolicy
#
# Every setting is optional: "Don't change" (donotconfigure) or blank must stay out of both
# the Set body and the compare, so the standard never writes a value nobody picked.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardTeamsFilesPolicy.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardTeamsFilesPolicy.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-TeamsRequestV2 { [CmdletBinding()] param($TenantFilter, $Type, $Action, $Identity, $Parameters) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardTeamsFilesPolicy' {
    BeforeEach {
        $script:SetParams = $null
        $script:Compare = $null

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $CurrentValue, $ExpectedValue)
            $script:Compare = @{ Current = $CurrentValue; Expected = $ExpectedValue }
        }
        Mock -CommandName New-TeamsRequestV2 -MockWith {
            param($Action, $Parameters)
            if ($Action -eq 'Set') { $script:SetParams = $Parameters; return }
            [pscustomobject]@{ Identity = 'Global'; FileSharingInChatsWithExternalUsers = 'Enabled'; NativeFileEntryPoints = 'Enabled'; SPChannelFilesTab = 'Enabled' }
        }
    }

    It 'writes only the settings that were picked' {
        $Settings = [pscustomobject]@{
            remediate                           = $true
            report                              = $true
            FileSharingInChatsWithExternalUsers = [pscustomobject]@{ label = 'Disabled'; value = 'Disabled' }
            NativeFileEntryPoints               = [pscustomobject]@{ label = "Don't change"; value = 'donotconfigure' }
            SPChannelFilesTab                   = $null
        }

        Invoke-CIPPStandardTeamsFilesPolicy -Tenant $script:Tenant -Settings $Settings

        $script:SetParams.Keys | Sort-Object | Should -Be @('FileSharingInChatsWithExternalUsers', 'Identity')
        $script:SetParams.FileSharingInChatsWithExternalUsers | Should -BeExactly 'Disabled'
        @($script:Compare.Expected.Keys) | Should -Be @('FileSharingInChatsWithExternalUsers')
        $script:Compare.Current.FileSharingInChatsWithExternalUsers | Should -BeExactly 'Enabled'
    }

    It 'does nothing and reports compliant when every setting is left on "Don''t change"' {
        $Settings = [pscustomobject]@{
            remediate                           = $true
            report                              = $true
            FileSharingInChatsWithExternalUsers = 'donotconfigure'
            NativeFileEntryPoints               = 'donotconfigure'
            SPChannelFilesTab                   = 'donotconfigure'
        }

        Invoke-CIPPStandardTeamsFilesPolicy -Tenant $script:Tenant -Settings $Settings

        $script:SetParams | Should -BeNullOrEmpty
        @($script:Compare.Expected.Keys).Count | Should -Be 0
    }

    It 'skips the write when the tenant already matches' {
        $Settings = [pscustomobject]@{ remediate = $true; FileSharingInChatsWithExternalUsers = 'Enabled' }

        Invoke-CIPPStandardTeamsFilesPolicy -Tenant $script:Tenant -Settings $Settings

        $script:SetParams | Should -BeNullOrEmpty
    }
}
