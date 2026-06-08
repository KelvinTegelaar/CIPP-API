function Test-CIPPStandardLicense {
    <#
    .SYNOPSIS
        Tests if a tenant has the required license capabilities for a specific standard
    .DESCRIPTION
        This function checks if a tenant has the necessary license capabilities to run a specific standard.
        If the license is missing, it logs an error and sets the comparison field appropriately.
    .PARAMETER StandardName
        The name of the standard to check licensing for
    .PARAMETER TenantFilter
        The tenant to check licensing for
    .PARAMETER RequiredCapabilities
        Array of required capabilities for the standard. Can be combined with Preset for edge cases.
    .PARAMETER Preset
        One or more predefined capability sets to check for the standard
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Test-CIPPStandardLicense -StandardName "ConditionalAccessTemplate" -TenantFilter "contoso.onmicrosoft.com" -RequiredCapabilities @('AADPremiumService')
    .EXAMPLE
        Test-CIPPStandardLicense -StandardName "SafeLinksPolicy" -TenantFilter "contoso.onmicrosoft.com" -RequiredCapabilities @('DEFENDER_FOR_OFFICE_365_PLAN_1', 'DEFENDER_FOR_OFFICE_365_PLAN_2')
    .EXAMPLE
        Test-CIPPStandardLicense -StandardName "TeamsGuestAccess" -TenantFilter "contoso.onmicrosoft.com" -Preset Teams
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StandardName,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string[]]$RequiredCapabilities,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Exchange', 'SharePoint', 'Intune', 'Entra', 'EntraP2', 'Teams', 'Compliance', 'DefenderForOffice365')]
        [string[]]$Preset,

        [Parameter(Mandatory = $false)]
        [switch]$SkipLog
    )

    $Presets = @{
        Exchange             = @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE',
            'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV',
            'EXCHANGE_LITE')
        SharePoint           = @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE',
            'SHAREPOINTENTERPRISE_EDU', 'SHAREPOINTENTERPRISE_GOV',
            'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')
        Intune               = @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')
        Entra                = @('AAD_PREMIUM', 'AAD_PREMIUM_P2')
        EntraP2              = @('AAD_PREMIUM_P2')
        Teams                = @('MCOSTANDARD', 'MCOEV', 'MCOIMP', 'TEAMS1', 'Teams_Room_Standard')
        Compliance           = @('RMS_S_PREMIUM', 'RMS_S_PREMIUM2', 'MIP_S_CLP1', 'MIP_S_CLP2')
        DefenderForOffice365 = @(
            'ATP_ENTERPRISE', 'ATP_ENTERPRISE_GOV',
            'THREAT_INTELLIGENCE', 'THREAT_INTELLIGENCE_GOV'
        )
    }

    if ((!$Preset -or $Preset.Count -eq 0) -and (!$RequiredCapabilities -or $RequiredCapabilities.Count -eq 0)) {
        throw 'Test-CIPPStandardLicense requires either -Preset or -RequiredCapabilities.'
    }

    if ($Preset) {
        $RequiredCapabilities = @(
            $RequiredCapabilities
            foreach ($CapabilityPreset in $Preset) {
                $Presets[$CapabilityPreset]
            }
        ) | Where-Object { $_ } | Select-Object -Unique
    }

    try {
        $TenantCapabilities = Get-CIPPTenantCapabilities -TenantFilter $TenantFilter

        $Capabilities = foreach ($Capability in $RequiredCapabilities) {
            Write-Verbose "Checking capability: $Capability"
            if ($TenantCapabilities.$Capability -eq $true) {
                $Capability
            }
        }

        if ($Capabilities.Count -le 0) {
            if (!$SkipLog.IsPresent) {
                Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "Tenant does not have the required capability to run standard $StandardName`: The tenant needs one of the following service plans: $($RequiredCapabilities -join ',')" -sev Info
                Set-CIPPStandardsCompareField -FieldName "standards.$StandardName" -LicenseAvailable $false -FieldValue "License Missing: This tenant is not licensed for the following capabilities: $($RequiredCapabilities -join ',')" -Tenant $TenantFilter
                Write-Verbose "Tenant does not have the required capability to run standard $StandardName - $($RequiredCapabilities -join ','). Exiting"
            }
            return $false
        }
        Write-Verbose "Tenant has the required capabilities for standard $StandardName"
        return $true
    } catch {
        if (!$SkipLog.IsPresent) {
            # Sanitize exception message to prevent JSON parsing issues - remove characters that could interfere with JSON detection
            $SanitizedMessage = $_.Exception.Message -replace '[{}\[\]]', ''
            Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "Error checking license capabilities for standard $StandardName`: $SanitizedMessage" -sev Info
            Set-CIPPStandardsCompareField -FieldName "standards.$StandardName" -FieldValue "License Missing: Error checking license capabilities - $SanitizedMessage" -Tenant $TenantFilter
        }
        return $false
    }
}
