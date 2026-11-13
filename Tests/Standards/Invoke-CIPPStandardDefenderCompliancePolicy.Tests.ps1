# Pester tests for the MDE connector writers: Invoke-CIPPStandardDefenderCompliancePolicy and
# Set-CIPPDefenderCompliancePolicy. Pins issue 1219: microsoftDefenderForEndpointAttachEnabled
# follows the AllowMEMEnforceCompliance switch instead of being forced on.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $body, $type, $AsApp) }
    function Enable-CIPPMDEConnector { [CmdletBinding()] param($TenantFilter) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . (Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardDefenderCompliancePolicy.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPDefenderCompliancePolicy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    # A connector as Graph returns it: every boolean surface false except the attach flag.
    function New-Connector {
        param([bool]$Attach)
        [pscustomobject]@{
            id                                                  = 'fc780465-2017-40d4-a0c5-307022471b92'
            partnerUnresponsivenessThresholdInDays              = 7
            androidEnabled                                      = $false
            iosEnabled                                          = $false
            windowsEnabled                                      = $false
            macEnabled                                          = $false
            partnerUnsupportedOsVersionBlocked                  = $false
            allowPartnerToCollectIOSApplicationMetadata         = $false
            allowPartnerToCollectIOSPersonalApplicationMetadata = $false
            androidDeviceBlockedOnMissingPartnerData            = $false
            iosDeviceBlockedOnMissingPartnerData                = $false
            windowsDeviceBlockedOnMissingPartnerData            = $false
            macDeviceBlockedOnMissingPartnerData                = $false
            androidMobileApplicationManagementEnabled           = $false
            iosMobileApplicationManagementEnabled               = $false
            windowsMobileApplicationManagementEnabled           = $false
            allowPartnerToCollectIosCertificateMetadata         = $false
            allowPartnerToCollectIosPersonalCertificateMetadata = $false
            grantMobileThreatDefensePartnerRole                 = $false
            microsoftDefenderForEndpointAttachEnabled           = $Attach
        }
    }
}

Describe 'MDE connector attach flag (issue 1219)' {
    BeforeEach {
        $script:Attach = $true
        Mock Enable-CIPPMDEConnector { [pscustomobject]@{ Success = $true; PartnerState = 'enabled' } }
        Mock New-GraphGetRequest { New-Connector -Attach $script:Attach }
        Mock New-GraphPOSTRequest { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    Context 'Invoke-CIPPStandardDefenderCompliancePolicy' {
        It 'turns the attach flag off when the switch is off and the tenant has it on' {
            Invoke-CIPPStandardDefenderCompliancePolicy -Tenant $script:Tenant -Settings ([pscustomobject]@{ remediate = $true; AllowMEMEnforceCompliance = $false })
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $type -eq 'PATCH' -and ($body | ConvertFrom-Json).microsoftDefenderForEndpointAttachEnabled -eq $false
            }
        }

        It 'treats a missing switch as off' {
            Invoke-CIPPStandardDefenderCompliancePolicy -Tenant $script:Tenant -Settings ([pscustomobject]@{ remediate = $true })
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                ($body | ConvertFrom-Json).microsoftDefenderForEndpointAttachEnabled -eq $false
            }
        }

        It 'turns the attach flag on when the switch is on and the tenant has it off' {
            $script:Attach = $false
            Invoke-CIPPStandardDefenderCompliancePolicy -Tenant $script:Tenant -Settings ([pscustomobject]@{ remediate = $true; AllowMEMEnforceCompliance = $true })
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                ($body | ConvertFrom-Json).microsoftDefenderForEndpointAttachEnabled -eq $true
            }
        }

        It 'does not write when the tenant already matches a switched-off attach flag' {
            $script:Attach = $false
            Invoke-CIPPStandardDefenderCompliancePolicy -Tenant $script:Tenant -Settings ([pscustomobject]@{ remediate = $true; AllowMEMEnforceCompliance = $false })
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'alerts and reports the switch as the expected value when the tenant has drifted to on' {
            Invoke-CIPPStandardDefenderCompliancePolicy -Tenant $script:Tenant -Settings ([pscustomobject]@{ alert = $true; report = $true; AllowMEMEnforceCompliance = $false })
            Should -Invoke Write-StandardsAlert -Times 1 -Exactly
            Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                $ExpectedValue.microsoftDefenderForEndpointAttachEnabled -eq $false -and $CurrentValue.microsoftDefenderForEndpointAttachEnabled -eq $true
            }
        }
    }

    Context 'Set-CIPPDefenderCompliancePolicy' {
        It 'writes the attach flag from the deployment switch' -ForEach @(
            @{ Switch = $false; Current = $true }
            @{ Switch = $true; Current = $false }
        ) {
            $script:Attach = $Current
            $null = Set-CIPPDefenderCompliancePolicy -TenantFilter $script:Tenant -Compliance ([pscustomobject]@{ AllowMEMEnforceCompliance = $Switch }) -APIName 'Test'
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $type -eq 'PATCH' -and ($body | ConvertFrom-Json).microsoftDefenderForEndpointAttachEnabled -eq $Switch
            }
        }

        It 'skips the write when the tenant already matches a switched-off attach flag' {
            $script:Attach = $false
            $null = Set-CIPPDefenderCompliancePolicy -TenantFilter $script:Tenant -Compliance ([pscustomobject]@{ AllowMEMEnforceCompliance = $false }) -APIName 'Test'
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }
    }
}
