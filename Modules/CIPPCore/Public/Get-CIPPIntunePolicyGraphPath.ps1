function Get-CIPPIntunePolicyGraphPath {
    <#
    .SYNOPSIS
        Maps an Intune policy's URLName / @odata.type to its Graph collection segment.
    .DESCRIPTION
        Single source of truth for the delete/read path of a policy. App protection
        policy lists expose the SINGULAR @odata.type as the URLName, but Graph needs the
        plural collection segment under deviceAppManagement; everything else lives under
        deviceManagement with its own collection name. Consumed by the RemovePolicy
        endpoint and by the baseline delete executor.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$UrlName
    )

    switch ($UrlName -replace '^#microsoft\.graph\.', '') {
        'androidManagedAppProtection' { 'deviceAppManagement/androidManagedAppProtections' }
        'iosManagedAppProtection' { 'deviceAppManagement/iosManagedAppProtections' }
        'windowsManagedAppProtection' { 'deviceAppManagement/windowsManagedAppProtections' }
        'mdmWindowsInformationProtectionPolicy' { 'deviceAppManagement/mdmWindowsInformationProtectionPolicies' }
        'windowsInformationProtectionPolicy' { 'deviceAppManagement/windowsInformationProtectionPolicies' }
        'targetedManagedAppConfiguration' { 'deviceAppManagement/targetedManagedAppConfigurations' }
        'managedAppPolicies' { 'deviceAppManagement/managedAppPolicies' }
        'mobileAppConfigurations' { 'deviceAppManagement/mobileAppConfigurations' }
        default { "deviceManagement/$UrlName" }
    }
}
