function Get-CIPPBaselineDevicePrepProfileState {
    <#
    .SYNOPSIS
        Prepare hook for DevicePrepProfile: one named Autopilot Device Preparation profile.
    .DESCRIPTION
        Finds the configured profile by name in the IntuneConfigurationPolicies cache and
        parses the enrollment_autopilot_dpp settings back into the classic's property set.
        The device security group resolves by name LIVE (the classic did the same lookup for
        its expected value); a group that does not exist yet grades as an empty id - the
        executor creates it when CreateNewGroup allows.

        The assignment grades separately through Compare-CIPPIntuneAssignments off the cached
        assignments; a failed or unknown lookup leaves the dimension out entirely, because a
        deviation no run can clear is worse than a blind spot. The settings verdict is
        carried for the executor so it can repair a wrong assignment IN PLACE instead of
        recreating the profile.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneConfigurationPolicies')) {
        return @{ Current = $null }
    }

    $V = $Item.Variables
    # The identity may arrive as an option object ({label, value}) from some save paths.
    $ProfileName = "$($V.ProfileName.value ?? $V.ProfileName)"
    if ([string]::IsNullOrWhiteSpace($ProfileName)) { return @{ Current = $null } }
    $Policy = @($Policies | Where-Object { "$($_.name)" -eq $ProfileName }) | Select-Object -First 1

    $DeploymentType = [string]($V.DeploymentType.value ?? $V.DeploymentType ?? '0')
    $JoinType = [string]($V.JoinType.value ?? $V.JoinType ?? '0')
    $AccountType = [string]($V.AccountType.value ?? $V.AccountType ?? '0')
    # Empty string means unset, exactly like a pruned remediate key: '' ?? falls through
    # and [int]'' is 0, which graded timeout 0 against the 60 the executor writes.
    $Timeout = if ([string]::IsNullOrWhiteSpace("$($V.Timeout)")) { 60 } else { [int]"$($V.Timeout)" }
    $CustomErrorMessage = if ([string]::IsNullOrWhiteSpace("$($V.CustomErrorMessage)")) { "Contact your organization$([char]0x2019)s support person for help." } else { "$($V.CustomErrorMessage)" }
    $AllowSkip = $(if ($V.AllowSkip -eq $true) { '1' } else { '0' })
    $AllowDiagnostics = $(if ($V.AllowDiagnostics -eq $true) { '1' } else { '0' })
    $AssignTo = [string]($V.AssignTo.value ?? $V.AssignTo ?? 'none')

    # Resolve the device security group by name, exactly the classic's lookup. Creation is
    # the executor's job - a compare must never write.
    $DeviceGroupId = ''
    if (-not [string]::IsNullOrWhiteSpace("$($V.DeviceGroupName)")) {
        try {
            $EscapedName = "$($V.DeviceGroupName)" -replace "'", "''"
            $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName') and mailEnabled eq false and securityEnabled eq true")
            $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $TenantFilter)
            if ($MatchedGroups.Count -gt 0) { $DeviceGroupId = "$($MatchedGroups[0].id)" }
        } catch {
            Write-Information "Baselines: DevicePrepProfile group lookup for '$($V.DeviceGroupName)' failed: $($_.Exception.Message)"
        }
    }

    $ChoiceSettingMap = @{
        'enrollment_autopilot_dpp_deploymentmode'   = 'deploymentMode'
        'enrollment_autopilot_dpp_deploymenttype'   = 'deploymentType'
        'enrollment_autopilot_dpp_jointype'         = 'joinType'
        'enrollment_autopilot_dpp_accountype'       = 'accountType'
        'enrollment_autopilot_dpp_allowskip'        = 'allowSkip'
        'enrollment_autopilot_dpp_allowdiagnostics' = 'allowDiagnostics'
    }
    $SimpleSettingMap = @{
        'enrollment_autopilot_dpp_timeout'                = 'timeout'
        'enrollment_autopilot_dpp_customerrormessage'     = 'customErrorMessage'
        'enrollment_autopilot_dpp_devicesecuritygroupids' = 'deviceGroupId'
    }
    $Parsed = @{}
    foreach ($Setting in @($Policy.settings)) {
        $Instance = $Setting.settingInstance
        $DefId = "$($Instance.settingDefinitionId)"
        if ($ChoiceSettingMap.ContainsKey($DefId)) {
            $Parsed[$ChoiceSettingMap[$DefId]] = ("$($Instance.choiceSettingValue.value)" -split '_')[-1]
        } elseif ($SimpleSettingMap.ContainsKey($DefId)) {
            $Parsed[$SimpleSettingMap[$DefId]] = $Instance.simpleSettingValue.value
        }
    }

    $Expected = [PSCustomObject]@{
        profileExists      = $true
        deploymentMode     = '0'
        deploymentType     = $DeploymentType
        joinType           = $JoinType
        accountType        = $AccountType
        timeout            = $Timeout
        customErrorMessage = $CustomErrorMessage
        allowSkip          = $AllowSkip
        allowDiagnostics   = $AllowDiagnostics
        deviceGroupId      = $DeviceGroupId
    }
    $Current = [PSCustomObject]@{
        profileExists      = ($null -ne $Policy)
        deploymentMode     = [string]($Parsed.deploymentMode ?? '')
        deploymentType     = [string]($Parsed.deploymentType ?? '')
        joinType           = [string]($Parsed.joinType ?? '')
        accountType        = [string]($Parsed.accountType ?? '')
        timeout            = [int]($Parsed.timeout ?? 0)
        customErrorMessage = [string]($Parsed.customErrorMessage ?? '')
        allowSkip          = [string]($Parsed.allowSkip ?? '')
        allowDiagnostics   = [string]($Parsed.allowDiagnostics ?? '')
        deviceGroupId      = [string]($Parsed.deviceGroupId ?? '')
    }

    # Assignment dimension: graded only when requested AND readable.
    $SettingsMatchedSoFar = $null -ne $Policy
    if ($SettingsMatchedSoFar -and $AssignTo -ne 'none') {
        try {
            $AssignmentDetail = Compare-CIPPIntuneAssignments -ExistingAssignments @($Policy.assignments) -ExpectedAssignTo $AssignTo -PolicyType 'DevicePrepProfile' -TenantFilter $TenantFilter
            if (-not $AssignmentDetail.Unknown) {
                $Expected | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $true
                $Current | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue ([bool]$AssignmentDetail.Matched)
            }
        } catch {
            Write-Information "Baselines: DevicePrepProfile assignment compare failed: $($_.Exception.Message)"
        }
    }

    # Carried for the executor: repair-in-place needs to know the settings verdict alone.
    $SettingsCorrect = $null -ne $Policy
    if ($SettingsCorrect) {
        foreach ($Prop in @('deploymentMode', 'deploymentType', 'joinType', 'accountType', 'allowSkip', 'allowDiagnostics', 'customErrorMessage', 'deviceGroupId')) {
            if ("$($Current.$Prop)" -ne "$($Expected.$Prop)") { $SettingsCorrect = $false; break }
        }
        if ($SettingsCorrect -and [int]$Current.timeout -ne [int]$Expected.timeout) { $SettingsCorrect = $false }
    }
    $Current | Add-Member -NotePropertyName 'policyId' -NotePropertyValue "$($Policy.id)"
    $Current | Add-Member -NotePropertyName 'settingsCorrect' -NotePropertyValue $SettingsCorrect

    @{ Expected = $Expected; Current = $Current }
}
