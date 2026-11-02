function Get-CIPPEnrollmentRestrictionProjection {
    <#
    .SYNOPSIS
        Projects enrollment restriction settings onto the fields that grade for its platform.
    .DESCRIPTION
        Takes the flat settings from ConvertTo-CIPPEnrollmentRestrictionSettings (a template)
        or ConvertFrom-CIPPEnrollmentRestrictionConfiguration (a tenant's restriction) and keeps
        only what the platform uses: the device administrator fields only for Android, OS
        versions everywhere but macOS, and manufacturers as a sorted list. Priority and the
        assignment are not part of it; callers grade those separately.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Settings,
        [Parameter(Mandatory = $true)]
        [string]$Platform
    )

    $Projection = [ordered]@{
        displayName = "$($Settings.displayName)"
        description = "$($Settings.description)"
    }
    foreach ($Type in @(Get-CIPPEnrollmentRestrictionPlatformTypes -Platform $Platform)) {
        $Fields = @('platformBlocked', 'personalDeviceEnrollmentBlocked')
        if ($Type.HasVersions) { $Fields += @('osMinimumVersion', 'osMaximumVersion') }
        foreach ($Field in $Fields) {
            $Name = $(if ($Type.Prefix) { "$($Type.Prefix)$($Field.Substring(0, 1).ToUpper())$($Field.Substring(1))" } else { $Field })
            $Projection[$Name] = $(if ($Field -like '*Blocked') { [bool]$Settings.$Name } else { "$($Settings.$Name)" })
        }
        if ($Type.HasManufacturers) {
            $Projection['deviceAdminBlockedManufacturers'] = (@($Settings.deviceAdminBlockedManufacturers) | Where-Object { $_ } | Sort-Object -Unique) -join ', '
        }
    }
    [PSCustomObject]$Projection
}
