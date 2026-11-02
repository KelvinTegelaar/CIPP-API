# Pester tests for Invoke-CIPPStandardTeamsMessagingPolicy
#
# AutoShareFilesInExternalChats was added after templates already existed: an unset or
# "Don't change" value must neither drift the compare nor reach the Set body.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardTeamsMessagingPolicy.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardTeamsMessagingPolicy.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-TeamsRequestV2 { [CmdletBinding()] param($TenantFilter, $Type, $Action, $Identity, $Parameters) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardTeamsMessagingPolicy AutoShareFilesInExternalChats' {
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
            [pscustomobject]@{
                AllowOwnerDeleteMessage                      = $false
                AllowUserDeleteMessage                       = $true
                AllowUserEditMessage                         = $true
                AllowUserDeleteChat                          = $true
                ReadReceiptsEnabledType                      = 'UserPreference'
                CreateCustomEmojis                           = $true
                DeleteCustomEmojis                           = $false
                AllowSecurityEndUserReporting                = $true
                AllowCommunicationComplianceEndUserReporting = $true
                AutoShareFilesInExternalChats                = 'Enabled'
            }
        }

        # A template saved before the setting existed, matching the tenant on every other field
        $script:Settings = @{ remediate = $true; report = $true; ReadReceiptsEnabledType = 'UserPreference' }
    }

    It 'treats a template without the setting as compliant' {
        Invoke-CIPPStandardTeamsMessagingPolicy -Tenant $script:Tenant -Settings $script:Settings

        $script:SetParams | Should -BeNullOrEmpty
        $script:Compare.Expected.AutoShareFilesInExternalChats | Should -BeExactly $script:Compare.Current.AutoShareFilesInExternalChats
    }

    It 'leaves "Don''t change" out of the Set body when another field drifts' {
        $script:Settings.AutoShareFilesInExternalChats = 'donotconfigure'
        $script:Settings.AllowOwnerDeleteMessage = $true

        Invoke-CIPPStandardTeamsMessagingPolicy -Tenant $script:Tenant -Settings $script:Settings

        $script:SetParams.ContainsKey('AutoShareFilesInExternalChats') | Should -BeFalse
    }

    It 'writes the picked value when it differs from the tenant' {
        $script:Settings.AutoShareFilesInExternalChats = ([pscustomobject]@{ label = 'Disabled'; value = 'Disabled' })

        Invoke-CIPPStandardTeamsMessagingPolicy -Tenant $script:Tenant -Settings $script:Settings

        $script:SetParams.AutoShareFilesInExternalChats | Should -BeExactly 'Disabled'
    }
}
