function Set-CIPPDBCacheIntunePolicies {
    <#
    .SYNOPSIS
        Caches all Intune policies for a tenant (if Intune capable)

    .PARAMETER TenantFilter
        The tenant to cache Intune policies for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntunePoliciesCache' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1') -SkipLog

        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping' -sev Info
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune policies' -sev Info

        $PolicyTypes = @(
            @{ Type = 'DeviceCompliancePolicies'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?$top=999' }
            @{ Type = 'DeviceConfigurations'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?$top=999' }
            @{ Type = 'ConfigurationPolicies'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$top=999' }
            @{ Type = 'GroupPolicyConfigurations'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?$top=999' }
            @{ Type = 'MobileAppConfigurations'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/mobileAppConfigurations?$top=999' }
            @{ Type = 'AppProtectionPolicies'; Uri = 'https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies?$top=999' }
            @{ Type = 'WindowsAutopilotDeploymentProfiles'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?$top=999' }
            @{ Type = 'DeviceEnrollmentConfigurations'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?$top=999' }
            @{ Type = 'DeviceManagementScripts'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?$top=999' }
            @{ Type = 'MobileApps'; Uri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?$top=999' }
        )

        foreach ($PolicyType in $PolicyTypes) {
            try {
                $Policies = New-GraphGetRequest -uri $PolicyType.Uri -tenantid $TenantFilter

                if ($Policies) {
                    Add-CIPPDbItem -TenantFilter $TenantFilter -Type "Intune$($PolicyType.Type)" -Data $Policies
                    Add-CIPPDbItem -TenantFilter $TenantFilter -Type "Intune$($PolicyType.Type)" -Data $Policies -Count
                    Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Policies.Count) $($PolicyType.Type)" -sev Info
                }

                $Policies = $null

            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache $($PolicyType.Type): $($_.Exception.Message)" -sev Warning
            }
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Intune policies successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune policies: $($_.Exception.Message)" -sev Error
    }
}
