function Get-CIPPBaselineAppleEnrollmentTypeProfileState {
    <#
    .SYNOPSIS
        Prepare hook for AppleEnrollmentTypeProfile: one named Apple user-initiated enrollment profile.
    .DESCRIPTION
        Finds the configured profile by display name in the Apple enrollment profiles cache and
        grades the classic's exact field set: description, default enrollment type and the
        available enrollment type options as a normalized ownerType:enrollmentType set, so
        option order coming back from Graph can never register as drift. Priority is not
        graded - it is relative to the other profiles in each tenant and only applied when the
        profile is first created.

        The assignment grades separately through Compare-CIPPIntuneAssignments off the cached
        assignments; a failed or unknown lookup - including a cache row whose assignments
        fetch failed, recognizable by the absent assignments property - leaves the dimension
        out entirely, because a deviation no run can clear is worse than a blind spot.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Profiles = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneAppleUserInitiatedEnrollmentProfiles')
    if ($Profiles.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneAppleUserInitiatedEnrollmentProfiles')) {
        return @{ Current = $null }
    }

    $V = $Item.Variables
    # The identity may arrive as an option object ({label, value}) from some save paths.
    $DisplayName = "$($V.DisplayName.value ?? $V.DisplayName)"
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return @{ Current = $null } }
    $EnrollmentProfile = @($Profiles | Where-Object { "$($_.displayName)" -eq $DisplayName }) | Select-Object -First 1

    $EnrollmentType = [string]($V.EnrollmentType.value ?? $V.EnrollmentType)
    if ([string]::IsNullOrWhiteSpace($EnrollmentType)) { $EnrollmentType = 'webDeviceEnrollment' }
    $AssignTo = [string]($V.AssignTo.value ?? $V.AssignTo)
    if ([string]::IsNullOrWhiteSpace($AssignTo)) { $AssignTo = 'none' }

    $CurrentOptions = (@($EnrollmentProfile.availableEnrollmentTypeOptions) | Where-Object { $_ } | ForEach-Object { "$($_.ownerType):$($_.enrollmentType)" } | Sort-Object) -join ', '

    $Expected = [PSCustomObject]@{
        profileExists         = $true
        displayName           = $DisplayName
        description           = "$($V.Description)"
        defaultEnrollmentType = $EnrollmentType
        enrollmentTypeOptions = "personal:$EnrollmentType"
    }
    $Current = [PSCustomObject]@{
        profileExists         = ($null -ne $EnrollmentProfile)
        displayName           = "$($EnrollmentProfile.displayName)"
        description           = "$($EnrollmentProfile.description)"
        defaultEnrollmentType = "$($EnrollmentProfile.defaultEnrollmentType)"
        enrollmentTypeOptions = $CurrentOptions
    }

    # Assignment dimension: graded only when requested AND readable. The collector only adds
    # the assignments property when the per-profile fetch succeeded, so a row without it is a
    # failed read - indistinguishable from "unassigned" by value, which is exactly why the
    # property's absence has to leave the dimension out instead of grading an empty set.
    if ($null -ne $EnrollmentProfile -and $AssignTo -ne 'none' -and $EnrollmentProfile.PSObject.Properties.Name -contains 'assignments') {
        try {
            $AssignmentDetail = Compare-CIPPIntuneAssignments -ExistingAssignments @($EnrollmentProfile.assignments) -ExpectedAssignTo $AssignTo -ExpectedCustomGroup "$($V.customGroup)" -PolicyType 'AppleEnrollmentTypeProfile' -TenantFilter $TenantFilter
            if (-not $AssignmentDetail.Unknown) {
                $Expected | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $true
                $Current | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue ([bool]$AssignmentDetail.Matched)
            }
        } catch {
            Write-Information "Baselines: AppleEnrollmentTypeProfile assignment compare failed: $($_.Exception.Message)"
        }
    }

    @{ Expected = $Expected; Current = $Current }
}
