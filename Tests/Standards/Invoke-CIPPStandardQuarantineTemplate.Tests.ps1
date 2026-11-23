# Pester tests for Invoke-CIPPStandardQuarantineTemplate
#
# Built-in quarantine policies (all-zero Guid) cannot be created or edited: New-QuarantinePolicy refuses
# the name and Set-QuarantinePolicy refuses the edit. A template entry using one of those names is skipped.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardQuarantineTemplate.ps1')

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $true }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams) }
    function Set-CIPPQuarantinePolicy { [CmdletBinding()] param($Action, $Identity, $EndUserQuarantinePermissions, $ESNEnabled, $IncludeMessagesFromBlockedSenderAddress, $tenantFilter, $APIName) }
    function Convert-QuarantinePermissionsValue { [CmdletBinding()] param($InputObject) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }

    function script:New-Entry { param([string]$Name) [PSCustomObject]@{ displayName = [PSCustomObject]@{ value = $Name; label = $Name }; ESNEnabled = $true; ReleaseAction = 'PermissionToRequestRelease'; remediate = $true } }
}

Describe 'Invoke-CIPPStandardQuarantineTemplate built-in policies' {
    BeforeEach {
        Mock New-ExoRequest { @(
                [PSCustomObject]@{ Name = 'DefaultFullAccessWithNotificationPolicy'; Guid = [guid]::Empty }
                [PSCustomObject]@{ Name = 'AdminOnlyAccessPolicy'; Guid = [guid]::Empty }
            ) }
        Mock Set-CIPPQuarantinePolicy {}
        Mock Write-LogMessage {}
    }

    It 'skips a built-in name with a warning instead of trying to create it' {
        Invoke-CIPPStandardQuarantineTemplate -Tenant 'contoso.com' -Settings @(New-Entry 'DefaultFullAccessWithNotificationPolicy')

        Should -Invoke Set-CIPPQuarantinePolicy -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*built-in*' }
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }

    It 'still creates a custom-named policy' {
        Invoke-CIPPStandardQuarantineTemplate -Tenant 'contoso.com' -Settings @(New-Entry 'Contoso Notify')

        Should -Invoke Set-CIPPQuarantinePolicy -Times 1 -Exactly -ParameterFilter { $Action -eq 'Create' -and $Identity -eq 'Contoso Notify' }
    }
}
