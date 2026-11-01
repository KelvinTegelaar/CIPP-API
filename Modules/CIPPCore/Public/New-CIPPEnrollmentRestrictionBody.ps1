function New-CIPPEnrollmentRestrictionBody {
    <#
    .SYNOPSIS
        Builds the Graph bodies for one enrollment restriction, one per Graph platform type.
    .DESCRIPTION
        Takes settings from ConvertTo-CIPPEnrollmentRestrictionSettings and returns an ordered
        dictionary of platform type -> deviceEnrollmentPlatformRestrictionConfiguration body.
        Android returns two bodies (androidForWork and android) with the same name, which is how
        the Intune portal stores an Android restriction.

        Blank OS versions are written as null, matching what the portal writes; macOS has no
        version limit, and only the device administrator half of Android blocks manufacturers.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    if ([string]::IsNullOrWhiteSpace($Settings.platform)) { throw 'Select the platform the restriction applies to.' }
    $Bodies = [ordered]@{}
    foreach ($Type in @(Get-CIPPEnrollmentRestrictionPlatformTypes -Platform $Settings.platform)) {
        $Field = { param($Name) if ($Type.Prefix) { "$($Type.Prefix)$($Name.Substring(0, 1).ToUpper())$($Name.Substring(1))" } else { $Name } }
        $Version = { param($Name) $Value = "$($Settings.(& $Field $Name))"; if ($Type.HasVersions -and $Value) { $Value } else { $null } }
        $Bodies[$Type.PlatformType] = [ordered]@{
            '@odata.type'       = '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration'
            displayName         = $Settings.displayName
            description         = "$($Settings.description)"
            platformType        = $Type.PlatformType
            platformRestriction = [ordered]@{
                platformBlocked                 = [bool]$Settings.(& $Field 'platformBlocked')
                personalDeviceEnrollmentBlocked = [bool]$Settings.(& $Field 'personalDeviceEnrollmentBlocked')
                osMinimumVersion                = & $Version 'osMinimumVersion'
                osMaximumVersion                = & $Version 'osMaximumVersion'
                blockedManufacturers            = @($(if ($Type.HasManufacturers) { $Settings.deviceAdminBlockedManufacturers }))
            }
        }
    }
    $Bodies
}
