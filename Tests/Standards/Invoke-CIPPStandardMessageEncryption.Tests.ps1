# Pester tests for Invoke-CIPPStandardMessageEncryption
#
# The standard enables Purview Message Encryption by turning on AzureRMSLicensingEnabled plus
# SimplifiedClientAccessEnabled (the Encrypt button in Outlook on the web / new Outlook). The one
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
    function Get-CippException { [CmdletBinding()] param($Exception) }

    . $StandardPath

    # Pester v5: anything assigned in a Describe body only exists during Discovery, so these live
    # here or they are $null by the time an It runs.
    $tenant = 'contoso.onmicrosoft.com'
    $AzureRmsLocation = 'https://5c6bb73b-1234.rms.na.aadrm.com/_wmcs/licensing'
    $AdRmsLocation = 'https://rms.contoso.local/_wmcs/licensing'

    function New-IRMConfig {
        param(
            $AzureRMSLicensingEnabled = $false,
            $SimplifiedClientAccessEnabled = $false,
            $LicensingLocation = @(),
            $EnablePdfEncryption = $false,
            $DecryptAttachmentForEncryptOnly = $false,
            $SimplifiedClientAccessDoNotForwardDisabled = $false,
            $SimplifiedClientAccessEncryptOnlyDisabled = $false,
            $TransportDecryptionSetting = 'Optional'
        )
        [pscustomobject]@{
            AzureRMSLicensingEnabled                   = $AzureRMSLicensingEnabled
            SimplifiedClientAccessEnabled              = $SimplifiedClientAccessEnabled
            LicensingLocation                          = $LicensingLocation
            EnablePdfEncryption                        = $EnablePdfEncryption
            DecryptAttachmentForEncryptOnly            = $DecryptAttachmentForEncryptOnly
            SimplifiedClientAccessDoNotForwardDisabled = $SimplifiedClientAccessDoNotForwardDisabled
            SimplifiedClientAccessEncryptOnlyDisabled  = $SimplifiedClientAccessEncryptOnlyDisabled
            TransportDecryptionSetting                 = $TransportDecryptionSetting
        }
    }

    # A tenant where the two mandatory settings are already right, so only the optional radios can
    # cause a Set-IRMConfiguration call.
    function New-AlignedIRMConfig {
        param([hashtable]$Overrides = @{})
        New-IRMConfig -AzureRMSLicensingEnabled $true -SimplifiedClientAccessEnabled $true -LicensingLocation @($AzureRmsLocation) @Overrides
    }
}

Describe 'Invoke-CIPPStandardMessageEncryption' {
    BeforeEach {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
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
        It 'enables Azure RMS licensing and the Encrypt button when message encryption is off' {
            Mock -CommandName New-ExoRequest -MockWith { New-IRMConfig -AzureRMSLicensingEnabled $false }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true }

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration' -and $cmdParams.AzureRMSLicensingEnabled -eq $true -and $cmdParams.SimplifiedClientAccessEnabled -eq $true
            }
        }

        It 'turns on the Encrypt button when licensing is on but simplified client access is off' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -AzureRMSLicensingEnabled $true -SimplifiedClientAccessEnabled $false -LicensingLocation @($AzureRmsLocation)
            }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true }

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration' -and $cmdParams.SimplifiedClientAccessEnabled -eq $true
            }
        }

        It 'does nothing when message encryption is already enabled' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -AzureRMSLicensingEnabled $true -SimplifiedClientAccessEnabled $true -LicensingLocation @($AzureRmsLocation)
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

    Context 'optional settings' {
        # The radios are tri-state: 'donotchange' (and a template saved before they existed) must
        # leave the tenant value alone, while an explicit 'false' must be enforced, not ignored.
        It 'leaves a setting alone when the radio is on do-not-change or missing' {
            Mock -CommandName New-ExoRequest -MockWith { New-AlignedIRMConfig @{ EnablePdfEncryption = $true } }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true; report = $true; EnablePdfEncryption = 'donotchange' }

            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'Set-IRMConfiguration' }
            Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                -not ($ExpectedValue.PSObject.Properties.Name -contains 'EnablePdfEncryption')
            }
        }

        It 'enables PDF encryption alongside the mandatory settings when asked' {
            Mock -CommandName New-ExoRequest -MockWith { New-IRMConfig -AzureRMSLicensingEnabled $false }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true; EnablePdfEncryption = 'true' }

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration' -and $cmdParams.AzureRMSLicensingEnabled -eq $true -and $cmdParams.EnablePdfEncryption -eq $true
            }
        }

        It 'enforces an explicit false instead of treating it as unset' {
            Mock -CommandName New-ExoRequest -MockWith { New-AlignedIRMConfig @{ DecryptAttachmentForEncryptOnly = $true } }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true; DecryptAttachmentForEncryptOnly = 'false' }

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration' -and $cmdParams.DecryptAttachmentForEncryptOnly -eq $false
            }
        }

        It 'sets the transport decryption mode when it drifts' {
            Mock -CommandName New-ExoRequest -MockWith { New-AlignedIRMConfig }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true; TransportDecryptionSetting = 'Mandatory' }

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-IRMConfiguration' -and $cmdParams.TransportDecryptionSetting -eq 'Mandatory'
            }
        }

        It 'ignores values that are not on the radio' {
            Mock -CommandName New-ExoRequest -MockWith { New-AlignedIRMConfig }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ remediate = $true; EnablePdfEncryption = 'yes'; TransportDecryptionSetting = 'Sometimes' }

            Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'Set-IRMConfiguration' }
        }

        It 'alerts with the names of the drifted optional settings' {
            Mock -CommandName New-ExoRequest -MockWith { New-AlignedIRMConfig }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ alert = $true; EnablePdfEncryption = 'true' }

            Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter {
                $message -match 'EnablePdfEncryption' -and $object.EnablePdfEncryption -eq $false
            }
        }

        It 'reports the chosen optional setting in both current and expected state' {
            Mock -CommandName New-ExoRequest -MockWith { New-AlignedIRMConfig }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ report = $true; EnablePdfEncryption = 'true' }

            Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                $CurrentValue.EnablePdfEncryption -eq $false -and
                $ExpectedValue.EnablePdfEncryption -eq $true -and
                $ExpectedValue.AdRmsDetected -eq $false
            }
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

        It 'alerts about the missing Encrypt button when only simplified client access is off' {
            Mock -CommandName New-ExoRequest -MockWith {
                New-IRMConfig -AzureRMSLicensingEnabled $true -SimplifiedClientAccessEnabled $false -LicensingLocation @($AzureRmsLocation)
            }

            Invoke-CIPPStandardMessageEncryption -Tenant $tenant -Settings @{ alert = $true }

            Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter {
                $message -match 'Encrypt button'
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
                New-IRMConfig -AzureRMSLicensingEnabled $true -SimplifiedClientAccessEnabled $true -LicensingLocation @($AzureRmsLocation)
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
                $CurrentValue.SimplifiedClientAccessEnabled -eq $false -and
                $CurrentValue.AdRmsDetected -eq $true -and
                $ExpectedValue.AzureRMSLicensingEnabled -eq $true -and
                $ExpectedValue.SimplifiedClientAccessEnabled -eq $true -and
                $ExpectedValue.AdRmsDetected -eq $false
            }
        }
    }
}
