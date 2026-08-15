function Get-CIPPBaselineDefaultPlatformRestrictionsState {
    <#
    .SYNOPSIS
        Prepare hook for DefaultPlatformRestrictions: the default enrollment platform
        restrictions.
    .DESCRIPTION
        Selected by an id SUFFIX rather than by type, and that is deliberate. The classic
        standard's own comment records why: Graph reports this object's
        deviceEnrollmentConfigurationType as either platformRestrictions or
        singlePlatformRestriction for the SAME object depending on how it was queried, so the
        type is not a reliable selector. The id always ends '_DefaultPlatformRestrictions'.

        Each platform contributes two booleans - whether the platform is blocked outright, and
        whether personally-owned devices of that platform are blocked - flattened here so the
        drift row names the platform that differs.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Configurations = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'DeviceEnrollmentConfigurations')
    if ($Configurations.Count -eq 0) { return @{ Current = $null } }

    $Config = @($Configurations | Where-Object { "$($_.id)".EndsWith('_DefaultPlatformRestrictions') }) | Select-Object -First 1
    if (-not $Config) { return @{ Current = $null } }

    $V = $Item.Variables
    $Map = @(
        @{ e = 'platformAndroidForWorkBlocked'; c = 'androidForWorkRestriction'; p = 'platformBlocked' }
        @{ e = 'personalAndroidForWorkBlocked'; c = 'androidForWorkRestriction'; p = 'personalDeviceEnrollmentBlocked' }
        @{ e = 'platformAndroidBlocked'; c = 'androidRestriction'; p = 'platformBlocked' }
        @{ e = 'personalAndroidBlocked'; c = 'androidRestriction'; p = 'personalDeviceEnrollmentBlocked' }
        @{ e = 'platformiOSBlocked'; c = 'iosRestriction'; p = 'platformBlocked' }
        @{ e = 'personaliOSBlocked'; c = 'iosRestriction'; p = 'personalDeviceEnrollmentBlocked' }
        @{ e = 'platformMacOSBlocked'; c = 'macOSRestriction'; p = 'platformBlocked' }
        @{ e = 'personalMacOSBlocked'; c = 'macOSRestriction'; p = 'personalDeviceEnrollmentBlocked' }
        @{ e = 'platformWindowsBlocked'; c = 'windowsRestriction'; p = 'platformBlocked' }
        @{ e = 'personalWindowsBlocked'; c = 'windowsRestriction'; p = 'personalDeviceEnrollmentBlocked' }
    )

    $Expected = [PSCustomObject]@{}
    $Current = [PSCustomObject]@{}
    foreach ($Entry in $Map) {
        $Expected | Add-Member -NotePropertyName $Entry.e -NotePropertyValue ([bool]($V.($Entry.e) -eq $true))
        $Current | Add-Member -NotePropertyName $Entry.e -NotePropertyValue ([bool]$Config.($Entry.c).($Entry.p))
    }
    $Current | Add-Member -NotePropertyName 'configurationId' -NotePropertyValue "$($Config.id)"

    @{ Expected = $Expected; Current = $Current }
}
