function Invoke-CIPPBaselineAppleEnrollmentTypeProfile {
    <#
    .SYNOPSIS
        AppleEnrollmentTypeProfile executor: deploys the named Apple enrollment type profile.
    .DESCRIPTION
        The classic's write, verbatim: create the profile when it is missing (the only moment
        priority is applied), PATCH the enrollment type, description and available options when
        the settings drifted, and reconcile the group assignments to exactly the configured
        set. The profile type has no /assign action, so missing groups are added and everything
        else is removed one assignment at a time. The profile and its assignments are read live
        rather than from the prepare's cache-derived state, because remediation must not act on
        a snapshot another remediation may already have changed.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $DisplayName = "$($Remediate.displayName.value ?? $Remediate.displayName)"
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return }

    $EnrollmentType = [string]($Remediate.enrollmentType.value ?? $Remediate.enrollmentType)
    if ([string]::IsNullOrWhiteSpace($EnrollmentType)) { $EnrollmentType = 'webDeviceEnrollment' }
    $Description = "$($Remediate.description)"
    $Priority = if ([string]::IsNullOrWhiteSpace("$($Remediate.priority)")) { 1 } else { [int]"$($Remediate.priority)" }
    $AssignTo = [string]($Remediate.assignTo.value ?? $Remediate.assignTo)
    if ([string]::IsNullOrWhiteSpace($AssignTo)) { $AssignTo = 'none' }

    $EnrollmentTypeOptions = @(
        @{
            '@odata.type'  = '#microsoft.graph.appleOwnerTypeEnrollmentType'
            ownerType      = 'personal'
            enrollmentType = $EnrollmentType
        }
    )

    $ProfilesUri = 'https://graph.microsoft.com/beta/deviceManagement/appleUserInitiatedEnrollmentProfiles'
    $Profiles = @(New-GraphGetRequest -uri "$ProfilesUri`?`$top=999" -tenantid $TenantFilter)
    $ExistingProfile = $Profiles | Where-Object { "$($_.displayName)" -eq $DisplayName } | Select-Object -First 1

    $ExistingAssignments = @()
    if (-not $ExistingProfile) {
        $CreateBody = @{
            '@odata.type'                  = '#microsoft.graph.appleUserInitiatedEnrollmentProfile'
            displayName                    = $DisplayName
            description                    = $Description
            platform                       = 'iOS'
            priority                       = $Priority
            defaultEnrollmentType          = $EnrollmentType
            availableEnrollmentTypeOptions = $EnrollmentTypeOptions
        } | ConvertTo-Json -Compress -Depth 10
        $NewProfile = New-GraphPostRequest -uri $ProfilesUri -tenantid $TenantFilter -body $CreateBody -type POST
        $ProfileId = "$($NewProfile.id)"
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created the Apple enrollment type profile '$DisplayName'." -Sev 'Info'
    } else {
        $ProfileId = "$($ExistingProfile.id)"
        # The settings verdict is recomputed from the live profile rather than carried over
        # from the prepare's cache-derived state: settings that drifted after the cache was
        # collected would otherwise survive a run that reports itself as remediated.
        $LiveOptions = (@($ExistingProfile.availableEnrollmentTypeOptions) | Where-Object { $_ } | ForEach-Object { "$($_.ownerType):$($_.enrollmentType)" } | Sort-Object) -join ', '
        $SettingsCorrect = ("$($ExistingProfile.description)" -eq $Description) -and
        ("$($ExistingProfile.defaultEnrollmentType)" -eq $EnrollmentType) -and
        ($LiveOptions -eq "personal:$EnrollmentType")
        if (-not $SettingsCorrect) {
            $PatchBody = @{
                '@odata.type'                  = '#microsoft.graph.appleUserInitiatedEnrollmentProfile'
                description                    = $Description
                defaultEnrollmentType          = $EnrollmentType
                availableEnrollmentTypeOptions = $EnrollmentTypeOptions
            } | ConvertTo-Json -Compress -Depth 10
            $null = New-GraphPostRequest -uri "$ProfilesUri/$ProfileId" -tenantid $TenantFilter -body $PatchBody -type PATCH
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated the Apple enrollment type profile '$DisplayName'." -Sev 'Info'
        }
        $ExistingAssignments = @(New-GraphGetRequest -uri "$ProfilesUri/$ProfileId/assignments" -tenantid $TenantFilter)
    }

    if ($AssignTo -ne 'customGroup' -or [string]::IsNullOrWhiteSpace($ProfileId)) { return }

    # Reconcile the assignments to exactly the configured groups.
    $ExpectedGroupIds = [System.Collections.Generic.List[string]]::new()
    $AllGroups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter
    foreach ($Name in @("$($Remediate.customGroup)".Split(',').Trim() | Where-Object { $_ })) {
        # Square brackets are wildcard character classes to -like; group names containing them
        # are literal. Matches the escaping Compare-CIPPIntuneAssignments applies.
        $Pattern = $Name -replace '\[', '`[' -replace '\]', '`]'
        $Matched = @($AllGroups | Where-Object { $_.displayName -like $Pattern } | Select-Object -ExpandProperty id)
        if ($Matched.Count -eq 0) {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "AppleEnrollmentTypeProfile: group name '$Name' matches no group in this tenant." -Sev 'Warning'
        } else {
            $ExpectedGroupIds.AddRange([string[]]$Matched)
        }
    }

    # A name set that resolves to nothing must not strip a working profile bare: the compare
    # keeps reporting the unresolved names, so deleting the existing assignments would add
    # damage to a deviation remediation cannot clear anyway.
    if ($ExpectedGroupIds.Count -eq 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "AppleEnrollmentTypeProfile: no configured group resolved for profile '$DisplayName'; leaving the existing assignments untouched." -Sev 'Warning'
        return
    }

    $ChangeCount = 0
    $KeptGroupIds = [System.Collections.Generic.List[string]]::new()
    foreach ($Assignment in $ExistingAssignments) {
        # An assignment filter set through Graph would otherwise survive as a kept assignment
        # while the comparison keeps flagging it - keep only clean group targets so the write
        # converges with what the compare asserts.
        $FilterId = "$($Assignment.target.deviceAndAppManagementAssignmentFilterId)"
        $HasFilter = -not [string]::IsNullOrWhiteSpace($FilterId) -and $FilterId -ne '00000000-0000-0000-0000-000000000000'
        $IsExpected = $Assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' -and $ExpectedGroupIds -contains "$($Assignment.target.groupId)" -and -not $HasFilter
        if ($IsExpected) {
            $KeptGroupIds.Add("$($Assignment.target.groupId)")
        } else {
            $null = New-GraphPostRequest -uri "$ProfilesUri/$ProfileId/assignments/$($Assignment.id)" -tenantid $TenantFilter -type DELETE
            $ChangeCount++
        }
    }
    foreach ($GroupId in @($ExpectedGroupIds | Select-Object -Unique | Where-Object { $_ -notin $KeptGroupIds })) {
        $AssignmentBody = @{
            target = @{
                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                groupId       = $GroupId
            }
        } | ConvertTo-Json -Compress -Depth 10
        $null = New-GraphPostRequest -uri "$ProfilesUri/$ProfileId/assignments" -tenantid $TenantFilter -body $AssignmentBody -type POST
        $ChangeCount++
    }
    if ($ChangeCount -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Reconciled the assignments for the Apple enrollment type profile '$DisplayName' ($ChangeCount change(s))." -Sev 'Info'
    }
}
