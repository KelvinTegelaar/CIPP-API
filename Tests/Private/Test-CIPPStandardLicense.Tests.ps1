BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTenantCapabilities.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPStandardLicense.ps1')
    function Get-CIPPTable { @{} }
    function Get-CIPPAzDataTableEntity { }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Add-CIPPAzDataTableEntity { }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    function Set-CIPPStandardsCompareField { param($FieldName, $FieldValue, $Tenant, $LicenseAvailable) }

    function Set-TenantPlans {
        param([hashtable]$Plans)
        $script:Plans = @(foreach ($Name in $Plans.Keys) { [pscustomobject]@{ servicePlanName = $Name; provisioningStatus = $Plans[$Name] } })
        Mock New-GraphGetRequest { [pscustomobject]@{ servicePlans = $script:Plans } }
    }
}

Describe 'Test-CIPPStandardLicense' {
    BeforeEach {
        $script:CIPPTenantCapabilitiesCache = $null
        Mock Write-LogMessage { }
        Mock Set-CIPPStandardsCompareField { }
    }

    It 'requires a preset or explicit capabilities' {
        { Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' } | Should -Throw '*requires either -Preset or -RequiredCapabilities*'
    }

    It 'returns true when the tenant has one of the required capabilities, without logging' {
        Set-TenantPlans @{ AAD_PREMIUM = 'Success'; EXCHANGE_S_ENTERPRISE = 'Success' }
        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -RequiredCapabilities 'AAD_PREMIUM_P2', 'AAD_PREMIUM' | Should -BeTrue
        Should -Invoke Write-LogMessage -Times 0 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
    }

    It 'matches capability names case-insensitively' {
        Set-TenantPlans @{ AAD_PREMIUM = 'Success' }
        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -RequiredCapabilities 'aad_premium' | Should -BeTrue
    }

    It 'does not count a disabled service plan' {
        Set-TenantPlans @{ AAD_PREMIUM = 'Disabled' }
        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -RequiredCapabilities 'AAD_PREMIUM' -SkipLog | Should -BeFalse
    }

    It 'counts a plan that is still provisioning' {
        Set-TenantPlans @{ TEAMS1 = 'PendingProvisioning' }
        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -Preset Teams | Should -BeTrue
    }

    It 'expands the <Preset> preset to <Plan>' -TestCases @(
        @{ Preset = 'Exchange'; Plan = 'EXCHANGE_LITE' }
        @{ Preset = 'SharePoint'; Plan = 'ONEDRIVE_ENTERPRISE' }
        @{ Preset = 'Intune'; Plan = 'MICROSOFTINTUNEPLAN1' }
        @{ Preset = 'Entra'; Plan = 'AAD_PREMIUM' }
        @{ Preset = 'EntraP2'; Plan = 'AAD_PREMIUM_P2' }
        @{ Preset = 'Compliance'; Plan = 'MIP_S_CLP2' }
        @{ Preset = 'DefenderForOffice365'; Plan = 'THREAT_INTELLIGENCE' }
    ) {
        param($Preset, $Plan)
        Set-TenantPlans @{ $Plan = 'Success' }
        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -Preset $Preset | Should -BeTrue
    }

    It 'does not let EntraP2 accept a P1 tenant' {
        Set-TenantPlans @{ AAD_PREMIUM = 'Success' }
        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -Preset EntraP2 -SkipLog | Should -BeFalse
    }

    It 'accepts a capability from either the preset or the explicit list' {
        Set-TenantPlans @{ CUSTOM_PLAN = 'Success' }
        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -Preset Entra -RequiredCapabilities 'CUSTOM_PLAN' | Should -BeTrue
    }

    It 'reports a missing licence with the capabilities it looked for' {
        Set-TenantPlans @{ EXCHANGE_S_ENTERPRISE = 'Success' }

        Test-CIPPStandardLicense -StandardName 'Std' -TenantFilter 'contoso.com' -RequiredCapabilities 'AAD_PREMIUM', 'AAD_PREMIUM_P2' | Should -BeFalse

        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $API -eq 'Standards' -and $tenant -eq 'contoso.com' -and $sev -eq 'Info' -and $message -like '*required capability to run standard Std*AAD_PREMIUM,AAD_PREMIUM_P2'
        }
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $FieldName -eq 'standards.Std' -and $LicenseAvailable -eq $false -and $Tenant -eq 'contoso.com' -and
            $FieldValue -eq 'License Missing: This tenant is not licensed for the following capabilities: AAD_PREMIUM,AAD_PREMIUM_P2'
        }
    }

    It 'lists each preset capability once in the missing-licence report' {
        Set-TenantPlans @{ OTHER = 'Success' }
        $null = Test-CIPPStandardLicense -StandardName 'Std' -TenantFilter 'contoso.com' -Preset Entra, EntraP2
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $FieldValue -eq 'License Missing: This tenant is not licensed for the following capabilities: AAD_PREMIUM,AAD_PREMIUM_P2'
        }
    }

    It 'writes nothing for a missing licence when -SkipLog is set' {
        Set-TenantPlans @{ OTHER = 'Success' }
        Test-CIPPStandardLicense -StandardName 'Std' -TenantFilter 'contoso.com' -Preset Entra -SkipLog | Should -BeFalse
        Should -Invoke Write-LogMessage -Times 0 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
    }

    It 'treats a failed lookup as unlicensed and reports the error without JSON brackets' {
        Mock New-GraphGetRequest { throw '{"error":{"message":"AADSTS53003 [blocked]"}}' }

        Test-CIPPStandardLicense -StandardName 'Std' -TenantFilter 'contoso.com' -Preset Entra | Should -BeFalse

        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $sev -eq 'Info' -and $message -like 'Error checking license capabilities for standard Std: *AADSTS53003 blocked*' -and $message -notmatch '[{}\[\]]'
        }
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $FieldName -eq 'standards.Std' -and $FieldValue -like 'License Missing: Error checking license capabilities - *AADSTS53003 blocked*' -and $null -eq $LicenseAvailable
        }
    }

    It 'writes nothing for a failed lookup when -SkipLog is set' {
        Mock New-GraphGetRequest { throw 'AADSTS53003' }
        Test-CIPPStandardLicense -StandardName 'Std' -TenantFilter 'contoso.com' -Preset Entra -SkipLog | Should -BeFalse
        Should -Invoke Write-LogMessage -Times 0 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
    }

    It 'reports a remembered lookup failure the same way without asking Graph again' {
        Mock New-GraphGetRequest { throw 'AADSTS53003: blocked by Conditional Access' }

        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -RequiredCapabilities 'AAD_PREMIUM' | Should -BeFalse
        Test-CIPPStandardLicense -StandardName 'Y' -TenantFilter 'contoso.com' -RequiredCapabilities 'AAD_PREMIUM' | Should -BeFalse

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 2 -Exactly -ParameterFilter { $FieldValue -like '*Error checking license capabilities - AADSTS53003*' }
    }

    It 'asks Graph again once the remembered failure has expired' {
        Mock New-GraphGetRequest { throw 'AADSTS53003: blocked by Conditional Access' }
        $null = Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -RequiredCapabilities 'AAD_PREMIUM' -SkipLog
        $script:CIPPTenantCapabilitiesCache['contoso.com'].Expires = [datetime]::UtcNow.AddSeconds(-1)
        $null = Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'contoso.com' -RequiredCapabilities 'AAD_PREMIUM' -SkipLog
        Should -Invoke New-GraphGetRequest -Times 2 -Exactly
    }

    It 'keeps one tenant failure from affecting another tenant' {
        Mock New-GraphGetRequest -ParameterFilter { $tenantid -eq 'broken.com' } { throw 'AADSTS53003' }
        Mock New-GraphGetRequest -ParameterFilter { $tenantid -eq 'fine.com' } { [pscustomobject]@{ servicePlans = @([pscustomobject]@{ servicePlanName = 'AAD_PREMIUM'; provisioningStatus = 'Success' }) } }

        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'broken.com' -Preset Entra -SkipLog | Should -BeFalse
        Test-CIPPStandardLicense -StandardName 'X' -TenantFilter 'fine.com' -Preset Entra | Should -BeTrue
    }
}
