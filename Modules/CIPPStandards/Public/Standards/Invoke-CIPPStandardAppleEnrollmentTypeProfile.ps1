function Invoke-CIPPStandardAppleEnrollmentTypeProfile {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AppleEnrollmentTypeProfile
    .SYNOPSIS
        (Label) Deploy Apple Enrollment Type Profile
    .DESCRIPTION
        (Helptext) Creates and manages an Apple user-initiated enrollment type profile (such as iOS/iPadOS web based device enrollment) and keeps it assigned to the configured groups. The tenant needs an Apple MDM push certificate for the enrollment itself to function.
        (DocsDescription) Deploys an Apple user-initiated enrollment type profile through deviceManagement/appleUserInitiatedEnrollmentProfiles. The profile is matched by display name; the enrollment type (web based device enrollment, account driven user enrollment, or device enrollment with Company Portal), description and group assignments are kept in sync, with a wrong assignment repaired in place. Priority is only applied when the profile is first created, because reordering is relative to the other profiles in each tenant.
    .NOTES
        CAT
            Intune Standards
        TAG
            "enrollment"
            "apple"
            "ios"
        EXECUTIVETEXT
            Ensures every tenant offers the same enrollment experience for Apple devices, such as web based enrollment for personal iPhones and iPads, without engineers configuring each tenant by hand. This keeps device onboarding consistent and makes it possible to report on which tenants are correctly configured.
        ADDEDCOMPONENT
            {"type":"textField","name":"standards.AppleEnrollmentTypeProfile.DisplayName","label":"Profile Display Name","required":true}
            {"type":"textField","name":"standards.AppleEnrollmentTypeProfile.Description","label":"Profile Description","required":false}
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"standards.AppleEnrollmentTypeProfile.EnrollmentType","label":"Enrollment Type","options":[{"label":"Web based device enrollment","value":"webDeviceEnrollment"},{"label":"Account driven user enrollment","value":"accountDrivenUserEnrollment"},{"label":"Device enrollment with Company Portal","value":"device"}]}
            {"type":"number","name":"standards.AppleEnrollmentTypeProfile.Priority","label":"Priority (applied when the profile is created)","defaultValue":1}
            {"type":"radio","name":"standards.AppleEnrollmentTypeProfile.AssignTo","label":"Profile Assignment","options":[{"label":"Do not assign","value":"none"},{"label":"Assign to Custom Group","value":"customGroup"}]}
            {"type":"textField","name":"standards.AppleEnrollmentTypeProfile.customGroup","label":"Custom group name(s). Comma separated, wildcards allowed.","required":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-08-18
        POWERSHELLEQUIVALENT
            Graph API - deviceManagement/appleUserInitiatedEnrollmentProfiles
        RECOMMENDEDBY
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        REQUIREDCAPABILITIES
            "INTUNE_A"
            "MDM_Services"
            "EMS"
            "SCCM"
            "MICROSOFTINTUNEPLAN1"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'AppleEnrollmentTypeProfile' -TenantFilter $Tenant -Preset Intune
    if ($TestResult -eq $false) { return $true }

    $DisplayName = "$($Settings.DisplayName)"
    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'AppleEnrollmentTypeProfile: DisplayName is empty, skipping.' -sev Error
        return
    }

    $EnrollmentType = [string]($Settings.EnrollmentType.value ?? $Settings.EnrollmentType)
    if ([string]::IsNullOrWhiteSpace($EnrollmentType)) { $EnrollmentType = 'webDeviceEnrollment' }
    $Description = "$($Settings.Description)"
    $Priority = if ([string]::IsNullOrWhiteSpace("$($Settings.Priority)")) { 1 } else { [int]"$($Settings.Priority)" }
    $AssignTo = [string]($Settings.AssignTo.value ?? $Settings.AssignTo ?? 'none')
    if ([string]::IsNullOrWhiteSpace($AssignTo)) { $AssignTo = 'none' }

    $ProfilesUri = 'https://graph.microsoft.com/beta/deviceManagement/appleUserInitiatedEnrollmentProfiles'
    try {
        $Profiles = @(New-GraphGetRequest -uri "$ProfilesUri`?`$top=999" -tenantid $Tenant)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Failed to retrieve enrollment type profiles: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }
    $ExistingProfile = $Profiles | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    $ProfileExists = $null -ne $ExistingProfile

    # The list endpoint does not expand assignments, so they are read per profile.
    $ExistingAssignments = @()
    $AssignmentsReadable = $false
    if ($ProfileExists) {
        try {
            $ExistingAssignments = @(New-GraphGetRequest -uri "$ProfilesUri/$($ExistingProfile.id)/assignments" -tenantid $Tenant)
            $AssignmentsReadable = $true
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Failed to read profile assignments: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
        }
    }

    # The available enrollment type options compare as a normalized ownerType:enrollmentType
    # set, so option order coming back from Graph can never register as drift.
    $CurrentOptions = (@($ExistingProfile.availableEnrollmentTypeOptions) | Where-Object { $_ } | ForEach-Object { "$($_.ownerType):$($_.enrollmentType)" } | Sort-Object) -join ', '
    $ExpectedOptions = "personal:$EnrollmentType"

    $AssignmentsMatch = $null
    $AssignmentDetail = $null
    if ($ProfileExists -and $AssignTo -ne 'none' -and $AssignmentsReadable) {
        try {
            $AssignmentDetail = Compare-CIPPIntuneAssignments -ExistingAssignments $ExistingAssignments -ExpectedAssignTo $AssignTo -ExpectedCustomGroup "$($Settings.customGroup)" -PolicyType 'AppleEnrollmentTypeProfile' -TenantFilter $Tenant
            # Unknown stays $null: a failed lookup is not a deviation.
            $AssignmentsMatch = if ($AssignmentDetail.Unknown) { $null } else { $AssignmentDetail.Matched }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Failed to compare profile assignments: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
        }
    }

    $CurrentValue = [PSCustomObject]@{
        profileExists         = $ProfileExists
        displayName           = "$($ExistingProfile.displayName)"
        description           = "$($ExistingProfile.description)"
        defaultEnrollmentType = "$($ExistingProfile.defaultEnrollmentType)"
        enrollmentTypeOptions = $CurrentOptions
    }
    $ExpectedValue = [PSCustomObject]@{
        profileExists         = $true
        displayName           = $DisplayName
        description           = $Description
        defaultEnrollmentType = $EnrollmentType
        enrollmentTypeOptions = $ExpectedOptions
    }

    # A failed assignment lookup is unknown, not a deviation: leave the dimension out of the
    # comparison entirely until it can be read, or drift records a deviation no run can clear.
    if ($AssignTo -ne 'none' -and $null -ne $AssignmentsMatch) {
        $CurrentValue | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $AssignmentsMatch
        $ExpectedValue | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $true
        if (-not $AssignmentsMatch) {
            $AssignmentReason = @($AssignmentDetail.Reasons) -join '; '
            if ($AssignmentReason) {
                $CurrentValue | Add-Member -NotePropertyName 'assignmentDifferences' -NotePropertyValue $AssignmentReason
            }
        }
    }

    # The settings verdict stays separate from the assignment verdict so remediation can repair
    # a wrong assignment in place instead of touching the profile itself.
    $SettingsAreCorrect = $ProfileExists -and
    ($CurrentValue.description -eq $ExpectedValue.description) -and
    ($CurrentValue.defaultEnrollmentType -eq $ExpectedValue.defaultEnrollmentType) -and
    ($CurrentValue.enrollmentTypeOptions -eq $ExpectedValue.enrollmentTypeOptions)
    $StateIsCorrect = $SettingsAreCorrect -and $AssignmentsMatch -ne $false

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Profile '$DisplayName' already correctly configured" -sev Info
        } else {
            try {
                $ProfileId = "$($ExistingProfile.id)"
                if (-not $ProfileExists) {
                    $CreateBody = @{
                        '@odata.type'                  = '#microsoft.graph.appleUserInitiatedEnrollmentProfile'
                        displayName                    = $DisplayName
                        description                    = $Description
                        platform                       = 'iOS'
                        priority                       = $Priority
                        defaultEnrollmentType          = $EnrollmentType
                        availableEnrollmentTypeOptions = @(
                            @{
                                '@odata.type' = '#microsoft.graph.appleOwnerTypeEnrollmentType'
                                ownerType     = 'personal'
                                enrollmentType = $EnrollmentType
                            }
                        )
                    } | ConvertTo-Json -Compress -Depth 10
                    $NewProfile = New-GraphPostRequest -uri $ProfilesUri -tenantid $Tenant -body $CreateBody -type POST
                    $ProfileId = "$($NewProfile.id)"
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Created profile '$DisplayName'" -sev Info
                } elseif (-not $SettingsAreCorrect) {
                    $PatchBody = @{
                        '@odata.type'                  = '#microsoft.graph.appleUserInitiatedEnrollmentProfile'
                        description                    = $Description
                        defaultEnrollmentType          = $EnrollmentType
                        availableEnrollmentTypeOptions = @(
                            @{
                                '@odata.type' = '#microsoft.graph.appleOwnerTypeEnrollmentType'
                                ownerType     = 'personal'
                                enrollmentType = $EnrollmentType
                            }
                        )
                    } | ConvertTo-Json -Compress -Depth 10
                    $null = New-GraphPostRequest -uri "$ProfilesUri/$ProfileId" -tenantid $Tenant -body $PatchBody -type PATCH
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Updated profile '$DisplayName'" -sev Info
                }

                # Reconcile the assignments to exactly the configured groups. The profile type has
                # no /assign action, so missing groups are added and everything else is removed
                # one assignment at a time.
                if ($AssignTo -eq 'customGroup' -and -not [string]::IsNullOrWhiteSpace($ProfileId) -and (-not $ProfileExists -or ($AssignmentsReadable -and $AssignmentsMatch -ne $true))) {
                    $ExpectedGroupIds = [System.Collections.Generic.List[string]]::new()
                    $AllGroups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $Tenant
                    foreach ($Name in @("$($Settings.customGroup)".Split(',').Trim() | Where-Object { $_ })) {
                        # Square brackets are wildcard character classes to -like; group names
                        # containing them are literal. Matches Compare-CIPPIntuneAssignments.
                        $Pattern = $Name -replace '\[', '`[' -replace '\]', '`]'
                        $Matched = @($AllGroups | Where-Object { $_.displayName -like $Pattern } | Select-Object -ExpandProperty id)
                        if ($Matched.Count -eq 0) {
                            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Group name '$Name' matches no group in this tenant" -sev Warning
                        } else {
                            $ExpectedGroupIds.AddRange([string[]]$Matched)
                        }
                    }

                    # A name set that resolves to nothing must not strip a working profile bare:
                    # the compare keeps reporting the unresolved names, so deleting the existing
                    # assignments would add damage to a deviation remediation cannot clear anyway.
                    if ($ExpectedGroupIds.Count -eq 0) {
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: No configured group resolved for profile '$DisplayName'; leaving the existing assignments untouched" -sev Warning
                    } else {
                        $KeptGroupIds = [System.Collections.Generic.List[string]]::new()
                        foreach ($Assignment in $ExistingAssignments) {
                            # An assignment filter set through Graph would otherwise survive as a
                            # kept assignment while the comparison keeps flagging it - keep only
                            # clean group targets so the write converges with the compare.
                            $FilterId = "$($Assignment.target.deviceAndAppManagementAssignmentFilterId)"
                            $HasFilter = -not [string]::IsNullOrWhiteSpace($FilterId) -and $FilterId -ne '00000000-0000-0000-0000-000000000000'
                            $IsExpected = $Assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget' -and $ExpectedGroupIds -contains "$($Assignment.target.groupId)" -and -not $HasFilter
                            if ($IsExpected) {
                                $KeptGroupIds.Add("$($Assignment.target.groupId)")
                            } else {
                                $null = New-GraphPostRequest -uri "$ProfilesUri/$ProfileId/assignments/$($Assignment.id)" -tenantid $Tenant -type DELETE
                            }
                        }
                        foreach ($GroupId in @($ExpectedGroupIds | Select-Object -Unique | Where-Object { $_ -notin $KeptGroupIds })) {
                            $AssignmentBody = @{
                                target = @{
                                    '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                                    groupId       = $GroupId
                                }
                            } | ConvertTo-Json -Compress -Depth 10
                            $null = New-GraphPostRequest -uri "$ProfilesUri/$ProfileId/assignments" -tenantid $Tenant -body $AssignmentBody -type POST
                        }
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Reconciled assignments for profile '$DisplayName'" -sev Info
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Failed to deploy profile '$DisplayName': $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Profile '$DisplayName' is correctly configured" -sev Info
        } else {
            Write-StandardsAlert -message "Apple enrollment type profile '$DisplayName' is not correctly configured" -object $CurrentValue -tenant $Tenant -standardName 'AppleEnrollmentTypeProfile' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "AppleEnrollmentTypeProfile: Profile '$DisplayName' is not correctly configured" -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.AppleEnrollmentTypeProfile' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
