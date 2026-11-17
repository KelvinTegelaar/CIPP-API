function Get-CIPPIntuneAssignmentSources {
    <#
    .SYNOPSIS
        The reporting cache types that hold Intune objects with their Graph assignments, and a label for each.
    .DESCRIPTION
        Shared by the group usage report and the per user/group/device assignment view so both read the same set.
        Scripts come before settings catalog policies because Linux scripts are also configuration policies.
    #>
    [CmdletBinding()]
    param()

    [ordered]@{
        IntuneWindowsScripts                       = 'Intune Platform Script'
        IntuneMacOSScripts                         = 'Intune Platform Script'
        IntuneLinuxScripts                         = 'Intune Platform Script'
        IntuneRemediationScripts                   = 'Intune Remediation Script'
        IntuneDeviceConfigurations                 = 'Intune Configuration Profile'
        IntuneConfigurationPolicies                = 'Intune Settings Catalog Policy'
        IntuneDeviceCompliancePolicies             = 'Intune Compliance Policy'
        IntuneGroupPolicyConfigurations            = 'Intune Administrative Template'
        IntuneAppProtectionMobileAppConfigurations = 'Intune App Configuration Policy'
        IntuneWindowsDriverUpdateProfiles          = 'Intune Driver Update Profile'
        IntuneWindowsFeatureUpdateProfiles         = 'Intune Feature Update Profile'
        IntuneWindowsQualityUpdatePolicies         = 'Intune Quality Update Policy'
        IntuneWindowsQualityUpdateProfiles         = 'Intune Quality Update Profile'
        IntuneHardwareConfigurations               = 'Intune Hardware Configuration'
        IntuneIntents                              = 'Intune Endpoint Security Policy'
        IntuneAppProtectionManagedAppPolicies      = 'Intune App Protection Policy'
        IntuneApplications                         = 'Intune Application'
        IntuneWindowsAutopilotDeploymentProfiles   = 'Autopilot Deployment Profile'
        IntuneDeviceEnrollmentConfigurations       = 'Intune Enrollment Configuration'
        IntuneAppleUserInitiatedEnrollmentProfiles = 'Apple Enrollment Profile'
    }
}
