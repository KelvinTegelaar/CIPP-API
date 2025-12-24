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
            @{ Type = 'DeviceCompliancePolicies'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies'; SupportsExpand = $true }
            @{ Type = 'DeviceConfigurations'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations'; SupportsExpand = $true }
            @{ Type = 'ConfigurationPolicies'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'; SupportsExpand = $true; ExpandSettings = $true }
            @{ Type = 'GroupPolicyConfigurations'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations'; SupportsExpand = $true }
            @{ Type = 'MobileAppConfigurations'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/mobileAppConfigurations'; SupportsExpand = $true }
            @{ Type = 'AppProtectionPolicies'; Uri = 'https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies'; SupportsExpand = $false }
            @{ Type = 'WindowsAutopilotDeploymentProfiles'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles'; SupportsExpand = $true }
            @{ Type = 'DeviceEnrollmentConfigurations'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations'; SupportsExpand = $false }
            @{ Type = 'DeviceManagementScripts'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts'; SupportsExpand = $true }
            @{ Type = 'MobileApps'; Uri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'; SupportsExpand = $false }
        )

        foreach ($PolicyType in $PolicyTypes) {
            try {
                $UriWithParams = $PolicyType.Uri + '?$top=999'
                if ($PolicyType.SupportsExpand) {
                    $UriWithParams += '&$expand=assignments'
                }
                if ($PolicyType.ExpandSettings) {
                    $UriWithParams += ',settings'
                }

                $Policies = New-GraphGetRequest -uri $UriWithParams -tenantid $TenantFilter

                if ($Policies) {
                    if (-not $PolicyType.SupportsExpand) {
                        foreach ($Policy in $Policies) {
                            try {
                                $AssignmentUri = "$($PolicyType.Uri)/$($Policy.id)/assignments"
                                $Assignments = New-GraphGetRequest -uri $AssignmentUri -tenantid $TenantFilter
                                $Policy | Add-Member -NotePropertyName 'assignments' -NotePropertyValue $Assignments -Force
                            } catch {
                                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to get assignments for $($Policy.id): $($_.Exception.Message)" -sev Verbose
                            }
                        }
                    }

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
