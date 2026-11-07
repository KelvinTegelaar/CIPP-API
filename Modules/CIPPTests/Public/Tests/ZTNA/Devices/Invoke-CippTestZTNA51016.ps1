function Invoke-CippTestZTNA51016 {
    <#
    .SYNOPSIS
    Privileged Identity Management is enforced for Intune Administrator role assignments
    #>
    param($Tenant)

    $TestId = 'ZTNA51016'
    $Name = 'Privileged Identity Management is enforced for Intune Administrator role assignments'
    $IntuneAdminRoleId = '3a2c62db-5318-420d-8d74-23affee5d9d5'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog) -or -not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset PIM -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for both Microsoft Intune and Privileged Identity Management (Microsoft Entra ID P2).' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $PolicyAssignments = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleManagementPolicies'
        $AssignmentInstances = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        if (-not $PolicyAssignments -or -not $AssignmentInstances) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. PIM role assignments and role management policies have not been collected yet.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $PolicyAssignment = $PolicyAssignments.Where({ $_.roleDefinitionId -eq $IntuneAdminRoleId -and $_.scopeId -eq '/' -and $_.scopeType -eq 'DirectoryRole' }, 'First')[0]
        if (-not $PolicyAssignment) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown '❌ No PIM role-management policy assignment was found for the Intune Administrator role. The role has no activation policy bound — PIM is not enforced.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
            return
        }

        $EnablementRule = @($PolicyAssignment.rules).Where({ $_.id -eq 'Enablement_EndUser_Assignment' }, 'First')[0]
        $ExpirationRule = @($PolicyAssignment.rules).Where({ $_.id -eq 'Expiration_EndUser_Assignment' }, 'First')[0]
        $HasMfa = [bool]($EnablementRule -and @($EnablementRule.enabledRules) -contains 'MultiFactorAuthentication')
        $HasJustification = [bool]($EnablementRule -and @($EnablementRule.enabledRules) -contains 'Justification')
        $IsExpirationRequired = [bool]($ExpirationRule -and $ExpirationRule.isExpirationRequired -eq $true)
        $MaxDurationRaw = $ExpirationRule.maximumDuration
        $MaxDurationOk = $false
        $MaxDurationParsed = $false
        if ($IsExpirationRequired -and $MaxDurationRaw) {
            try {
                $MaxDuration = [System.Xml.XmlConvert]::ToTimeSpan($MaxDurationRaw)
                $MaxDurationParsed = $true
                $MaxDurationOk = $MaxDuration.TotalSeconds -gt 0 -and $MaxDuration.TotalSeconds -le 28800
            } catch {
                $MaxDurationParsed = $false
            }
        }

        $IntuneAdminInstances = $AssignmentInstances.Where({ $_.roleDefinitionId -eq $IntuneAdminRoleId })
        $PrincipalIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($IntuneAdminInstances.principalId), [System.StringComparer]::OrdinalIgnoreCase)
        $UsersById = @{}
        if ($PrincipalIds.Count -gt 0) {
            foreach ($User in (Get-CIPPTestData -TenantFilter $Tenant -Type 'Users')) {
                if ($User.id -and $PrincipalIds.Contains([string]$User.id)) { $UsersById[[string]$User.id] = $User }
            }
        }

        # The cached principal carries no userType/accountEnabled; an unresolved user is counted as standing access
        $InstanceRows = foreach ($Instance in $IntuneAdminInstances) {
            $User = $UsersById[[string]$Instance.principalId]
            $IsUser = $Instance.principal.'@odata.type' -eq '#microsoft.graph.user'
            $IsStanding = $Instance.assignmentType -eq 'Assigned' -and $null -eq $Instance.endDateTime -and $IsUser -and
                (-not $User -or ($User.userType -eq 'Member' -and $User.accountEnabled -eq $true))
            [PSCustomObject]@{
                Instance   = $Instance
                Enabled    = if (-not $IsUser) { '-' } elseif (-not $User) { 'Unknown' } elseif ($User.accountEnabled -eq $true) { 'Yes' } else { 'No' }
                IsStanding = $IsStanding
            }
        }
        $InstanceRows = @($InstanceRows)
        $StandingCount = $InstanceRows.Where({ $_.IsStanding }).Count

        $Passed = $HasMfa -and $HasJustification -and $IsExpirationRequired -and $MaxDurationOk -and $StandingCount -eq 0
        $Summary = if ($Passed) {
            '✅ The Intune Administrator role is managed with safe privileged-access controls — no enabled Member user has standing permanent Intune Administrator access, and PIM activations require MFA, justification, and a bounded duration.'
        } else {
            '❌ The Intune Administrator role is not adequately protected — one or more enabled Member users has standing permanent Intune Administrator access, or the activation policy is missing MFA / justification / duration limits.'
        }

        $PortalUrl = 'https://portal.azure.com/#view/Microsoft_Azure_PIMCommon/CommonMenuBlade/~/aadmigratedroles'
        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`n## [PIM eligibility (Informational)]($PortalUrl)`n`n| Principal | Type | Member type | Eligibility window | Status |`n| :-------- | :--- | :---------- | :----------------- | :----- |`n")
        $Eligible = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleEligibilitySchedules').Where({ $_.roleDefinitionId -eq $IntuneAdminRoleId })
        if ($Eligible.Count -gt 0) {
            foreach ($Schedule in $Eligible.Where({ $true }, 'First', 10)) {
                $PrincipalName = if ($Schedule.principal.displayName) { $Schedule.principal.displayName } else { $Schedule.principalId }
                $PrincipalType = if ($Schedule.principal.'@odata.type') { $Schedule.principal.'@odata.type' -replace '#microsoft.graph\.', '' } else { 'Unknown' }
                $Expiration = $Schedule.scheduleInfo.expiration
                $Start = if ($Schedule.scheduleInfo.startDateTime) { $Schedule.scheduleInfo.startDateTime } else { 'N/A' }
                $End = if ($Expiration.endDateTime) { $Expiration.endDateTime } elseif ($Expiration.duration -and $Expiration.type -ne 'noExpiration') { $Expiration.duration } else { 'Permanent' }
                $MemberType = if ($Schedule.memberType) { $Schedule.memberType } else { '-' }
                $ScheduleStatus = if ($Schedule.status) { $Schedule.status } else { '-' }
                $null = $ResultMarkdown.Append("| $PrincipalName | $PrincipalType | $MemberType | $Start → $End | $ScheduleStatus |`n")
            }
            if ($Eligible.Count -gt 10) {
                $null = $ResultMarkdown.Append("`n_**Note**: This table is truncated and showing the first 10 of $($Eligible.Count) eligible assignments._`n")
            }
        } else {
            $ActivatedCount = $IntuneAdminInstances.Where({ $_.assignmentType -eq 'Activated' }).Count
            if ($ActivatedCount -gt 0) {
                $null = $ResultMarkdown.Append("| *(No persisted eligibility schedules, but $ActivatedCount current PIM activation(s) confirm PIM is in use)* | | | | |`n")
            } else {
                $null = $ResultMarkdown.Append("| *No eligible assignments found* | | | | |`n")
            }
        }

        $DurationDisplay = if ($MaxDurationRaw) { $MaxDurationRaw } else { 'Not set' }
        $DurationStatus = if ($MaxDurationOk) { '✅ Pass' } elseif (-not $IsExpirationRequired) { '❌ Fail (expiration not required)' } elseif (-not $MaxDurationParsed) { '❌ Fail (duration not parseable)' } else { "❌ Fail ($DurationDisplay exceeds PT8H)" }
        $null = $ResultMarkdown.Append("`n## [Activation policy rules]($PortalUrl)`n`n| Rule | Setting | Value | Required value | Status |`n| :--- | :------ | :---- | :------------- | :----- |`n")
        $null = $ResultMarkdown.Append("| Enablement | MFA on activation | $(if ($HasMfa) { 'Yes' } else { 'No' }) | Yes | $(if ($HasMfa) { '✅ Pass' } else { '❌ Fail' }) |`n")
        $null = $ResultMarkdown.Append("| Enablement | Justification required | $(if ($HasJustification) { 'Yes' } else { 'No' }) | Yes | $(if ($HasJustification) { '✅ Pass' } else { '❌ Fail' }) |`n")
        $null = $ResultMarkdown.Append("| Expiration | Activation must expire | $($IsExpirationRequired.ToString().ToLower()) | true | $(if ($IsExpirationRequired) { '✅ Pass' } else { '❌ Fail' }) |`n")
        $null = $ResultMarkdown.Append("| Expiration | Maximum activation duration | $DurationDisplay | ≤PT8H | $DurationStatus |`n")

        $null = $ResultMarkdown.Append("`n## [Standing permanent assignments]($PortalUrl)`n`n| Principal | UPN | Assignment type | Member type | End time | Enabled | Status |`n| :-------- | :-- | :-------------- | :---------- | :------- | :------ | :----- |`n")
        if ($InstanceRows.Count -gt 0) {
            foreach ($Row in $InstanceRows.Where({ $true }, 'First', 10)) {
                $Instance = $Row.Instance
                $PrincipalName = if ($Instance.principal.displayName) { $Instance.principal.displayName } else { $Instance.principalId }
                $Upn = if ($Instance.principal.userPrincipalName) { $Instance.principal.userPrincipalName } else { '-' }
                $EndTime = if ($null -eq $Instance.endDateTime) { 'Permanent' } else { $Instance.endDateTime }
                $RowStatus = if ($Row.IsStanding) { '❌ Fail' } else { '✅ Pass' }
                $null = $ResultMarkdown.Append("| $PrincipalName | $Upn | $($Instance.assignmentType) | $($Instance.memberType) | $EndTime | $($Row.Enabled) | $RowStatus |`n")
            }
            if ($InstanceRows.Count -gt 10) {
                $null = $ResultMarkdown.Append("`n_**Note**: This table is truncated and showing the first 10 of $($InstanceRows.Count) role assignment instances._`n")
            }
        } else {
            $null = $ResultMarkdown.Append("| _no rows returned — no enabled Member user holds standing Intune Administrator_ | | | | | | ✅ Pass |`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Devices'
    }
}
