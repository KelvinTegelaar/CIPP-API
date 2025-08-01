function Get-CIPPURLName {
    <#
    .SYNOPSIS
        Gets the correct Microsoft Graph URL based on the OData type of a template
    .DESCRIPTION
        This function examines the @odata.type property of a JSON template object and returns
        the appropriate full Microsoft Graph API URL for that resource type.
    .PARAMETER Template
        The template object containing the @odata.type property to analyze
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPURLName -Template $MyTemplate
    .EXAMPLE
        $Template | Get-CIPPURLName
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSCustomObject]$Template
    )

    # Extract the OData type from the template
    $ODataType = $Template.'@odata.type'
    if ($Template.urlName) { return $Template.urlName }

    if (-not $ODataType) {
        Write-Warning 'No @odata.type property found in template'
        return $null
    }

    # Determine the full Microsoft Graph URL based on the OData type
    $URLName = switch -wildcard ($ODataType) {
        # Device Compliance Policies
        '*CompliancePolicy' {
            'deviceManagement/deviceCompliancePolicies'
        }
        '*deviceCompliancePolicy' {
            'deviceManagement/deviceCompliancePolicies'
        }

        # Managed App Policies (App Protection)
        '*ManagedAppProtection' {
            'deviceAppManagement/managedAppPolicies'
        }
        '*managedAppPolicies' {
            'deviceAppManagement/managedAppPolicies'
        }
        '*managedAppPolicy' {
            'deviceAppManagement/managedAppPolicies'
        }
        '*appProtectionPolicy' {
            'deviceAppManagement/managedAppPolicies'
        }

        # Configuration Policies (Settings Catalog)
        '*configurationPolicies' {
            'deviceManagement/configurationPolicies'
        }
        '*deviceManagementConfigurationPolicy' {
            'deviceManagement/configurationPolicies'
        }

        # Windows Driver Update Profiles
        '*windowsDriverUpdateProfiles' {
            'deviceManagement/windowsDriverUpdateProfiles'
        }
        '*windowsDriverUpdateProfile' {
            'deviceManagement/windowsDriverUpdateProfiles'
        }

        # Device Configurations
        '*deviceConfigurations' {
            'deviceManagement/deviceConfigurations'
        }
        '*deviceConfiguration' {
            'deviceManagement/deviceConfigurations'
        }

        # Group Policy Configurations (Administrative Templates)
        '*groupPolicyConfigurations' {
            'deviceManagement/groupPolicyConfigurations'
        }
        '*groupPolicyConfiguration' {
            'deviceManagement/groupPolicyConfigurations'
        }

        # Conditional Access Policies
        '*conditionalAccessPolicy' {
            'identity/conditionalAccess/policies'
        }

        # Device Enrollment Configurations
        '*deviceEnrollmentConfiguration' {
            'deviceManagement/deviceEnrollmentConfigurations'
        }
        '*enrollmentConfiguration' {
            'deviceManagement/deviceEnrollmentConfigurations'
        }

        # Mobile App Configurations
        '*mobileAppConfiguration' {
            'deviceAppManagement/mobileAppConfigurations'
        }
        '*appConfiguration' {
            'deviceAppManagement/mobileAppConfigurations'
        }

        # Windows Feature Update Profiles
        '*windowsFeatureUpdateProfile' {
            'deviceManagement/windowsFeatureUpdateProfiles'
        }

        # Device Health Scripts (Remediation Scripts)
        '*deviceHealthScript' {
            'deviceManagement/deviceHealthScripts'
        }

        # Device Management Scripts (PowerShell Scripts)
        '*deviceManagementScript' {
            'deviceManagement/deviceManagementScripts'
        }

        # Mobile Applications
        '*mobileApp' {
            'deviceAppManagement/mobileApps'
        }
        '*winGetApp' {
            'deviceAppManagement/mobileApps'
        }
        '*officeSuiteApp' {
            'deviceAppManagement/mobileApps'
        }

        # Named Locations
        '*namedLocation' {
            'identity/conditionalAccess/namedLocations'
        }
        '*ipNamedLocation' {
            'identity/conditionalAccess/namedLocations'
        }
        '*countryNamedLocation' {
            'identity/conditionalAccess/namedLocations'
        }

        # Default fallback
        default {
            Write-Warning "Unknown OData type: $ODataType"
            $null
        }
    }

    return $URLName
}

