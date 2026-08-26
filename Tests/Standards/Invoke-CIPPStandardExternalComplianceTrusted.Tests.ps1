# Pester tests for Invoke-CIPPStandardExternalComplianceTrusted.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardExternalComplianceTrusted.ps1'

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { [CmdletBinding()] param($tenantid, $uri, $type, $body, $AsApp, $ContentType) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardExternalComplianceTrusted' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock New-GraphGetRequest {
            [PSCustomObject]@{
                inboundTrust = [PSCustomObject]@{
                    isMfaAccepted = $false
                    isCompliantDeviceAccepted = $false
                    isHybridAzureADJoinedDeviceAccepted = $true
                }
            }
        }
        Mock New-GraphPostRequest { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
        Mock Add-CIPPBPAField { }
    }

    It 'remediates compliant-device trust without resetting sibling trust flags' {
        Invoke-CIPPStandardExternalComplianceTrusted -Tenant $script:Tenant -Settings @{ remediate = $true; state = 'true' }

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'patch' -and
            ($body | ConvertFrom-Json).inboundTrust.isCompliantDeviceAccepted -eq $true -and
            ($body | ConvertFrom-Json).inboundTrust.isMfaAccepted -eq $false -and
            ($body | ConvertFrom-Json).inboundTrust.isHybridAzureADJoinedDeviceAccepted -eq $true
        }
    }

    It 'reports the compliant-device property as the comparison field' {
        Invoke-CIPPStandardExternalComplianceTrusted -Tenant $script:Tenant -Settings @{ report = $true; state = 'true' }

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $FieldName -eq 'standards.ExternalComplianceTrusted' -and
            $CurrentValue.isCompliantDeviceAccepted -eq $false -and
            $ExpectedValue.isCompliantDeviceAccepted -eq $true
        }
        Should -Invoke Add-CIPPBPAField -Times 1 -Exactly -ParameterFilter {
            $FieldName -eq 'ExternalComplianceTrusted' -and $FieldValue -eq $false
        }
    }
}
