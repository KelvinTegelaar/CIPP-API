BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardEwsAppIdAllowList.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    $Tenant = 'contoso.onmicrosoft.com'
    $AppId1 = '11111111-2222-3333-4444-555555555555'
    $AppId2 = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
}

Describe 'Invoke-CIPPStandardEwsAppIdAllowList' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
        Mock Add-CIPPBPAField { }
    }

    It 'does not access Exchange when the tenant is not licensed' {
        Mock Test-CIPPStandardLicense { $false }
        Mock New-ExoRequest { }

        Invoke-CIPPStandardEwsAppIdAllowList -Tenant $Tenant -Settings @{ remediate = $true; AllowedAppIds = @($AppId1) }

        Should -Invoke New-ExoRequest -Times 0 -Exactly
    }

    It 'rejects an empty allow list without accessing Exchange' {
        Mock New-ExoRequest { }

        Invoke-CIPPStandardEwsAppIdAllowList -Tenant $Tenant -Settings @{ remediate = $true; AllowedAppIds = @() }

        Should -Invoke New-ExoRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -match 'At least one' }
    }

    It 'rejects malformed application IDs without accessing Exchange' {
        Mock New-ExoRequest { }

        Invoke-CIPPStandardEwsAppIdAllowList -Tenant $Tenant -Settings @{ remediate = $true; AllowedAppIds = @('not-a-guid') }

        Should -Invoke New-ExoRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -match 'Invalid Entra' }
    }

    It 'treats ordering, casing, duplicates, and UI value wrappers as equivalent' {
        Mock New-ExoRequest {
            [pscustomobject]@{ EwsEnabled = $true; EwsAllowedAppIDs = "$AppId1,$($AppId2.ToUpperInvariant())" }
        }

        Invoke-CIPPStandardEwsAppIdAllowList -Tenant $Tenant -Settings @{
            remediate = $true
            AllowedAppIds = @([pscustomobject]@{ value = $AppId2 }, $AppId1, $AppId1)
        }

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Get-OrganizationConfig' }
        Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'Set-OrganizationConfig' }
    }

    It 'writes the complete normalized list and verifies readback' {
        Mock New-ExoRequest {
            if ($cmdlet -eq 'Set-OrganizationConfig') { return }
            if ($script:ReadCount++ -eq 0) {
                return [pscustomobject]@{ EwsEnabled = $null; EwsAllowedAppIDs = $null }
            }
            return [pscustomobject]@{ EwsEnabled = $true; EwsAllowedAppIDs = "$AppId1,$AppId2" }
        }
        $script:ReadCount = 0

        Invoke-CIPPStandardEwsAppIdAllowList -Tenant $Tenant -Settings @{
            remediate = $true
            AllowedAppIds = @($AppId2, $AppId1)
        }

        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-OrganizationConfig' -and
            $cmdParams.EwsEnabled -eq $true -and
            $cmdParams.EwsAllowedAppIDs -eq "$AppId1,$AppId2"
        }
        Should -Invoke New-ExoRequest -Times 2 -Exactly -ParameterFilter { $cmdlet -eq 'Get-OrganizationConfig' }
    }

    It 'alerts when the current policy differs' {
        Mock New-ExoRequest { [pscustomobject]@{ EwsEnabled = $false; EwsAllowedAppIDs = $AppId1 } }

        Invoke-CIPPStandardEwsAppIdAllowList -Tenant $Tenant -Settings @{
            alert = $true
            standardId = 'standard-1'
            AllowedAppIds = @($AppId1)
        }

        Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter {
            $standardName -eq 'EwsAppIdAllowList' -and $standardId -eq 'standard-1'
        }
    }

    It 'reports normalized current and expected values' {
        Mock New-ExoRequest { [pscustomobject]@{ EwsEnabled = $true; EwsAllowedAppIDs = $AppId1 } }

        Invoke-CIPPStandardEwsAppIdAllowList -Tenant $Tenant -Settings @{ report = $true; AllowedAppIds = @($AppId1) }

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $FieldName -eq 'standards.EwsAppIdAllowList' -and
            $CurrentValue.EwsEnabled -eq $true -and
            $ExpectedValue.EwsAllowedAppIDs[0] -eq $AppId1
        }
        Should -Invoke Add-CIPPBPAField -Times 1 -Exactly -ParameterFilter { $FieldValue -eq $true }
    }
}
