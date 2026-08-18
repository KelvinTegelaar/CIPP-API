# Pester tests for Invoke-CIPPStandardMessageEncryption
#
# The standard enables Purview Message Encryption by turning on AzureRMSLicensingEnabled. The one
# case it must NOT act on is a tenant still pointed at an on-premises AD RMS cluster: Purview
# Message Encryption is incompatible with AD RMS, so remediating there would silently half-configure
# a tenant that first needs a migration. That skip is what these tests pin down.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardMessageEncryption.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardMessageEncryption.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift in the standard fail loudly here instead of silently landing in
    # $args and leaving the captured value $null.
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $RequiredCapabilities, $Preset, [switch]$SkipLog) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-CippException { [CmdletBinding()] param($Exception) }

    . $StandardPath

    # Pester v5: anything assigned in a Describe body only exists during Discovery, so these live
    # here or they are $null by the time an It runs.
    $tenant = 'contoso.onmicrosoft.com'
    $AzureRmsLocation = 'https://5c6bb73b-1234.rms.na.aadrm.com/_wmcs/licensing'
    $AdRmsLocation = 'https://rms.contoso.local/_wmcs/licensing'

    function New-IRMConfig {
        param($AzureRMSLicensingEnabled = $false, $LicensingLocation = @())
        [pscustomobject]@{
            AzureRMSLicensingEnabled = $AzureRMSLicensingEnabled
            LicensingLocation        = $LicensingLocation
        }
    }
}

Describe 'Invoke-CIPPStandardMessageEncryption' {
    BeforeEach {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = 'boom' } }
    }

    Context 'licensing guard' {
        It 'bails out when the tenant is not licensed' {
            Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }
            Mock -CommandName New-ExoRequest -MockWith { New-IRMConfig }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true }

            Should -Invoke New-ExoRequest -Times 0 -Exactly
        }
    }

    Context 'remediation' {
        It 'enables Azure RMS licensing when message encryption is off' {
            Mock -CommandName New-ExoRequest -MockWith { New-IRMConfig -AzureRMSLicensingEnabled $false }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true }

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration' -and $cmdParams.AzureRMSLicensingEnabled -eq $true
            }
        }

        It 'does nothing when message encryption is already enabled' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -AzureRMSLicensingEnabled $true -LicensingLocation @($AzureRmsLocation)
            }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true }

            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration'
            }
        }

        It 'refuses to remediate a tenant that still uses on-premises AD RMS' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -AzureRMSLicensingEnabled $false -LicensingLocation @($AdRmsLocation)
            }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true }

            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration'
            }
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $sev -eq 'Warning' -and $message -match 'AD RMS'
            }
        }

        It 'does not remediate when the Exchange read fails' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'no exchange for you' }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true }

            Should -Invoke New-ExoRequest -Times 1 -Exactly
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
        }
    }

    Context 'alerting' {
        It 'alerts when message encryption is disabled' {
            Mock -CommandName New-ExoRequest -MockWith { New-IRMConfig -AzureRMSLicensingEnabled $false }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ alert = $true }

            Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter {
                $message -match 'not enabled'
            }
        }

        It 'alerts about the AD RMS blocker even when Azure RMS licensing is on' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -AzureRMSLicensingEnabled $true -LicensingLocation @($AdRmsLocation)
            }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ alert = $true }

            Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter {
                $message -match 'AD RMS'
            }
        }

        It 'stays quiet when the tenant is correctly configured' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -AzureRMSLicensingEnabled $true -LicensingLocation @($AzureRmsLocation)
            }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ alert = $true }

            Should -Invoke Write-StandardsAlert -Times 0 -Exactly
        }
    }

    Context 'reporting' {
        It 'reports the current and expected IRM state' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -AzureRMSLicensingEnabled $false -LicensingLocation @($AdRmsLocation)
            }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ report = $true }

            Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                $FieldName -eq 'standards.MessageEncryption' -and
                $CurrentValue.AzureRMSLicensingEnabled -eq $false -and
                $CurrentValue.AdRmsDetected -eq $true -and
                $ExpectedValue.AzureRMSLicensingEnabled -eq $true -and
                $ExpectedValue.AdRmsDetected -eq $false
            }
            Should -Invoke Add-CIPPBPAField -Times 1 -Exactly -ParameterFilter {
                $FieldName -eq 'messageEncryptionEnabled' -and $FieldValue -eq $false
            }
        }
    }
}
