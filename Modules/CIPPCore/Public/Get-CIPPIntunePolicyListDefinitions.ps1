function Get-CIPPIntunePolicyListDefinitions {
    <#
    .SYNOPSIS
        Returns the canonical Intune policy families shown by ListIntunePolicy.

    .DESCRIPTION
        Keeps the live endpoint, reporting cache collector, and cached report reader
        aligned on policy family identifiers, cache keys, Graph requests, and fallback
        policy type labels. CacheUri may request additional fields needed by standards
        and reports while preserving the same collection and filters as GraphUri.
    #>
    [CmdletBinding()]
    param()

    @(
        [PSCustomObject]@{
            Id                  = 'DeviceConfigurations'
            CacheType           = 'IntuneDeviceConfigurations'
            GraphUri            = '/deviceManagement/deviceConfigurations?$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName,description&$expand=assignments&$top=1000'
            CacheUri            = '/deviceManagement/deviceConfigurations?$top=999&$expand=assignments'
            PolicyTypeName      = $null
            FetchDeviceStatuses = $true
        }
        [PSCustomObject]@{
            Id             = 'WindowsDriverUpdateProfiles'
            CacheType      = 'IntuneWindowsDriverUpdateProfiles'
            GraphUri       = '/deviceManagement/windowsDriverUpdateProfiles?$expand=assignments&$top=200'
            CacheUri       = '/deviceManagement/windowsDriverUpdateProfiles?$expand=assignments&$top=200'
            PolicyTypeName = 'Driver Update'
        }
        [PSCustomObject]@{
            Id             = 'WindowsFeatureUpdateProfiles'
            CacheType      = 'IntuneWindowsFeatureUpdateProfiles'
            GraphUri       = '/deviceManagement/windowsFeatureUpdateProfiles?$expand=assignments&$top=200'
            CacheUri       = '/deviceManagement/windowsFeatureUpdateProfiles?$expand=assignments&$top=200'
            PolicyTypeName = 'Feature Update'
        }
        [PSCustomObject]@{
            Id             = 'windowsQualityUpdatePolicies'
            CacheType      = 'IntuneWindowsQualityUpdatePolicies'
            GraphUri       = '/deviceManagement/windowsQualityUpdatePolicies?$expand=assignments&$top=200'
            CacheUri       = '/deviceManagement/windowsQualityUpdatePolicies?$expand=assignments&$top=200'
            PolicyTypeName = 'Quality Update'
        }
        [PSCustomObject]@{
            Id             = 'windowsQualityUpdateProfiles'
            CacheType      = 'IntuneWindowsQualityUpdateProfiles'
            GraphUri       = '/deviceManagement/windowsQualityUpdateProfiles?$expand=assignments&$top=200'
            CacheUri       = '/deviceManagement/windowsQualityUpdateProfiles?$expand=assignments&$top=200'
            PolicyTypeName = 'Quality Update'
        }
        [PSCustomObject]@{
            Id             = 'GroupPolicyConfigurations'
            CacheType      = 'IntuneGroupPolicyConfigurations'
            GraphUri       = '/deviceManagement/groupPolicyConfigurations?$expand=assignments&$top=1000'
            CacheUri       = '/deviceManagement/groupPolicyConfigurations?$expand=assignments&$top=1000'
            PolicyTypeName = 'Administrative Templates'
        }
        [PSCustomObject]@{
            Id             = 'MobileAppConfigurations'
            CacheType      = 'IntuneMobileAppConfigurations'
            GraphUri       = '/deviceAppManagement/mobileAppConfigurations?$expand=assignments&$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true'
            CacheUri       = '/deviceAppManagement/mobileAppConfigurations?$expand=assignments&$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true'
            PolicyTypeName = $null
        }
        [PSCustomObject]@{
            Id             = 'ConfigurationPolicies'
            CacheType      = 'IntuneConfigurationPolicies'
            GraphUri       = '/deviceManagement/configurationPolicies?$expand=assignments&$top=1000'
            CacheUri       = '/deviceManagement/configurationPolicies?$expand=assignments,settings&$top=1000'
            PolicyTypeName = 'Device Configuration'
        }
        [PSCustomObject]@{
            Id                  = 'deviceCompliancePolicies'
            CacheType           = 'IntuneDeviceCompliancePolicies'
            GraphUri            = '/deviceManagement/deviceCompliancePolicies?$expand=assignments&$top=1000'
            CacheUri            = '/deviceManagement/deviceCompliancePolicies?$expand=assignments&$top=1000'
            PolicyTypeName      = 'Compliance Policy'
            FetchDeviceStatuses = $true
        }
        [PSCustomObject]@{
            Id             = 'Intents'
            CacheType      = 'IntuneIntents'
            GraphUri       = '/deviceManagement/intents?$top=1000'
            CacheUri       = '/deviceManagement/intents?$top=1000'
            PolicyTypeName = 'Endpoint Security'
        }
        [PSCustomObject]@{
            Id               = 'ManagedAppPolicies'
            CacheType        = 'IntuneAppProtectionPolicies'
            GraphUri         = '/deviceAppManagement/managedAppPolicies?$orderby=displayName'
            CacheUri         = '/deviceAppManagement/managedAppPolicies?$orderby=displayName'
            PolicyTypeName   = 'App Protection'
            # Assignments are exposed by the concrete managed app policy resources,
            # not the generic collection used by the live policy list.
            FetchAssignments = $false
        }
    )
}
