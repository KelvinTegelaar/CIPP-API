function ConvertTo-CIPPEnrollmentRestrictionSettings {
    <#
    .SYNOPSIS
        Normalises any enrollment restriction input into CIPP's flat settings shape.
    .DESCRIPTION
        The create drawer, the template forms, saved templates, rows from
        ListEnrollmentRestrictions and baseline variables all describe a restriction with the same
        property names. This reads them case-insensitively, unwraps option objects
        ({ value, label }), turns switch strings into booleans and blank values into empty strings,
        so every caller compares and writes the same thing.

        The flat shape is: displayName, description, platform (android, ios, macOS or windows),
        priority (null when unset), the unprefixed platform settings, the deviceAdmin* settings
        for the Android device administrator half, and the assignment in the same AssignTo and
        customGroup fields Intune templates use. AssignTo is normalised by
        Get-CIPPIntuneAssignTarget; enrollment restrictions apply to users, so only
        allLicensedUsers and customGroup assign, and anything else is 'On' (do not assign).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $InputObject
    )

    $Read = {
        param($Name)
        $Value = $InputObject.$Name
        # Only a single option object is unwrapped; arrays (group names, manufacturers) pass through.
        $IsOption = ($Value -is [hashtable] -and $Value.ContainsKey('value')) -or
        ($Value -is [System.Management.Automation.PSCustomObject] -and $Value.PSObject.Properties.Name -contains 'value')
        if ($IsOption) { $Value = $Value.value }
        $Value
    }
    $Text = { param($Name) "$(& $Read $Name)".Trim() }
    $Switch = { param($Name) "$(& $Read $Name)" -eq 'true' }
    $List = { param($Name) @(@(& $Read $Name) | ForEach-Object { "$($_.value ?? $_)".Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

    $Platform = & $Text 'platform'
    $Platform = @((Get-CIPPEnrollmentRestrictionPlatformTypes).Keys | Where-Object { $_ -eq $Platform }) | Select-Object -First 1
    $PriorityText = & $Text 'priority'
    $Priority = $null
    if (-not [string]::IsNullOrWhiteSpace($PriorityText)) {
        $Parsed = 0
        if (-not [int]::TryParse($PriorityText, [ref]$Parsed) -or $Parsed -lt 1) { throw "Priority must be a whole number of 1 or more, not '$PriorityText'." }
        $Priority = $Parsed
    }
    $AssignTo = (Get-CIPPIntuneAssignTarget -AssignTo (& $Read 'AssignTo')).AssignTo
    if ($AssignTo -notin @('allLicensedUsers', 'customGroup')) { $AssignTo = 'On' }

    [PSCustomObject][ordered]@{
        displayName                                = & $Text 'displayName'
        description                                = & $Text 'description'
        platform                                   = "$Platform"
        priority                                   = $Priority
        platformBlocked                            = & $Switch 'platformBlocked'
        personalDeviceEnrollmentBlocked            = & $Switch 'personalDeviceEnrollmentBlocked'
        osMinimumVersion                           = & $Text 'osMinimumVersion'
        osMaximumVersion                           = & $Text 'osMaximumVersion'
        deviceAdminPlatformBlocked                 = & $Switch 'deviceAdminPlatformBlocked'
        deviceAdminPersonalDeviceEnrollmentBlocked = & $Switch 'deviceAdminPersonalDeviceEnrollmentBlocked'
        deviceAdminOsMinimumVersion                = & $Text 'deviceAdminOsMinimumVersion'
        deviceAdminOsMaximumVersion                = & $Text 'deviceAdminOsMaximumVersion'
        deviceAdminBlockedManufacturers            = @(& $List 'deviceAdminBlockedManufacturers' | Sort-Object -Unique)
        AssignTo                                   = $AssignTo
        customGroup                                = (@(& $List 'customGroup' | Select-Object -Unique)) -join ', '
    }
}
