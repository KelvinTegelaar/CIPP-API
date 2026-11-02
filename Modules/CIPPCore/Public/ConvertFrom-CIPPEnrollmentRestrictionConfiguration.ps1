function ConvertFrom-CIPPEnrollmentRestrictionConfiguration {
    <#
    .SYNOPSIS
        Groups a tenant's single-platform restriction objects into CIPP enrollment restrictions.
    .DESCRIPTION
        Reads deviceEnrollmentConfigurations (other configuration types are skipped) and groups the
        singlePlatformRestriction objects by display name and CIPP platform, so the two objects
        behind an Android restriction come back as one. Each result carries the flat settings from
        ConvertTo-CIPPEnrollmentRestrictionSettings plus:

        - ids: every Graph object behind the restriction
        - priority: the lowest (highest precedence) priority among them
        - AssignTo / customGroup / groupIds / assignments: read from the objects' assignments when
          present; customGroup names come from -GroupNameById, falling back to the id, and the raw
          assignments are kept for Compare-CIPPIntuneAssignments
        - missingPlatformTypes: Graph types the platform needs but the tenant does not have,
          such as an Android restriction created with only one half
        - isDefault: false

        Assignments are read from the first object that has them; the portal assigns both
        Android halves together.

        -IncludeDefault also returns the tenant's default restriction once per platform, as the
        portal lists it at the bottom of each platform tab: isDefault true, no priority and no
        assignment. That includes tvOS and visionOS, which only the default carries in Graph. The default is one object with a block per platform type, so its ids hold that
        one object's id.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Configurations,
        [hashtable]$GroupNameById = @{},
        [switch]$IncludeDefault
    )

    $PlatformByType = @{}
    $Map = Get-CIPPEnrollmentRestrictionPlatformTypes
    foreach ($Platform in $Map.Keys) { foreach ($Type in $Map[$Platform]) { $PlatformByType[$Type.PlatformType] = $Platform } }

    # Fills a platform's flat settings from the Graph restriction block of each of its types, keyed
    # by DefaultProperty (set for every type, including tvOS and visionOS, which have no platform type).
    $AddRestrictionSettings = {
        param($Flat, $Types, [hashtable]$RestrictionByProperty)
        foreach ($Type in $Types) {
            $Prefix = $Type.Prefix
            $Name = { param($Field) if ($Prefix) { "$Prefix$($Field.Substring(0, 1).ToUpper())$($Field.Substring(1))" } else { $Field } }
            $Restriction = $RestrictionByProperty[$Type.DefaultProperty]
            $Flat[(& $Name 'platformBlocked')] = [bool]$Restriction.platformBlocked
            $Flat[(& $Name 'personalDeviceEnrollmentBlocked')] = [bool]$Restriction.personalDeviceEnrollmentBlocked
            $Flat[(& $Name 'osMinimumVersion')] = "$($Restriction.osMinimumVersion)"
            $Flat[(& $Name 'osMaximumVersion')] = "$($Restriction.osMaximumVersion)"
            if ($Type.HasManufacturers) { $Flat['deviceAdminBlockedManufacturers'] = @($Restriction.blockedManufacturers) }
        }
    }

    $Restrictions = @($Configurations | Where-Object {
            "$($_.'@odata.type')" -match 'deviceEnrollmentPlatformRestrictionConfiguration$' -and $PlatformByType.ContainsKey("$($_.platformType)")
        })

    foreach ($Group in ($Restrictions | Group-Object -Property { "$($PlatformByType["$($_.platformType)"])|$($_.displayName)" })) {
        $Objects = @($Group.Group)
        $Platform = $PlatformByType["$($Objects[0].platformType)"]
        $Flat = [ordered]@{
            displayName = "$($Objects[0].displayName)"
            description = "$($Objects[0].description)"
            platform    = $Platform
        }
        $RestrictionByProperty = @{}
        foreach ($Type in $Map[$Platform]) {
            $RestrictionByProperty[$Type.DefaultProperty] = ($Objects | Where-Object { "$($_.platformType)" -eq $Type.PlatformType } | Select-Object -First 1).platformRestriction
        }
        & $AddRestrictionSettings $Flat $Map[$Platform] $RestrictionByProperty

        $Assigned = $Objects | Where-Object { $_.PSObject.Properties.Name -contains 'assignments' } | Select-Object -First 1
        $Assignments = @($Assigned.assignments | Where-Object { $_ })
        $GroupIds = @($Assignments.target | Where-Object { "$($_.'@odata.type')" -eq '#microsoft.graph.groupAssignmentTarget' } | ForEach-Object { "$($_.groupId)" } | Where-Object { $_ } | Sort-Object -Unique)
        $Flat['AssignTo'] = $(if (@($Assignments.target | Where-Object { "$($_.'@odata.type')" -eq '#microsoft.graph.allLicensedUsersAssignmentTarget' }).Count -gt 0) { 'allLicensedUsers' } elseif ($GroupIds.Count -gt 0) { 'customGroup' } else { 'On' })
        $Flat['customGroup'] = @($GroupIds | ForEach-Object { $GroupNameById[$_] ?? $_ })

        $Settings = ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject ([PSCustomObject]$Flat)
        $Priorities = @($Objects | ForEach-Object { $_.priority } | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ } | Sort-Object)
        $Settings.priority = $(if ($Priorities.Count -gt 0) { $Priorities[0] } else { $null })
        $Settings | Add-Member -NotePropertyMembers ([ordered]@{
                ids                  = @($Objects | ForEach-Object { "$($_.id)" })
                groupIds             = $GroupIds
                assignments          = $Assignments
                missingPlatformTypes = @($Map[$Platform] | Where-Object { $_.PlatformType -notin @($Objects.platformType) } | ForEach-Object { $_.PlatformType })
                lastModifiedDateTime = @($Objects | ForEach-Object { $_.lastModifiedDateTime } | Sort-Object -Descending)[0]
                assignmentsKnown     = $null -ne $Assigned
                isDefault            = $false
            })
        $Settings
    }

    if (-not $IncludeDefault) { return }
    # The id always ends '_DefaultPlatformRestrictions'; its @odata.type is not a reliable selector.
    $Default = @($Configurations | Where-Object { "$($_.id)".EndsWith('_DefaultPlatformRestrictions') }) | Select-Object -First 1
    if (-not $Default) { return }
    $DefaultMap = Get-CIPPEnrollmentRestrictionPlatformTypes -IncludeDefaultOnly
    foreach ($Platform in $DefaultMap.Keys) {
        $Flat = [ordered]@{
            displayName = "$($Default.displayName)"
            description = "$($Default.description)"
            platform    = $Platform
        }
        $RestrictionByProperty = @{}
        foreach ($Type in $DefaultMap[$Platform]) { $RestrictionByProperty[$Type.DefaultProperty] = $Default.($Type.DefaultProperty) }
        & $AddRestrictionSettings $Flat $DefaultMap[$Platform] $RestrictionByProperty

        $Settings = ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject ([PSCustomObject]$Flat)
        # Settings only accept platforms a restriction can be created for; tvOS and visionOS are display-only.
        $Settings.platform = $Platform
        $Settings | Add-Member -NotePropertyMembers ([ordered]@{
                ids                  = @("$($Default.id)")
                groupIds             = @()
                assignments          = @()
                missingPlatformTypes = @()
                lastModifiedDateTime = $Default.lastModifiedDateTime
                assignmentsKnown     = $false
                isDefault            = $true
            })
        $Settings
    }
}
