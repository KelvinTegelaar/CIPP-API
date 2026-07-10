function Test-E8AsrRule {
    <#
    .SYNOPSIS
    Internal helper used by E8 Macro/AppHard tests to verify a single Defender ASR rule child setting is enabled and assigned.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Tenant,
        [Parameter(Mandatory)] [string] $TestId,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RuleSettingId,
        [Parameter(Mandatory)] [string] $FriendlyRule,
        [string] $Risk = 'High',
        [string] $Category,
        [string] $UserImpact = 'Medium',
        [string] $ImplementationEffort = 'Medium'
    )

    try {
        $ConfigPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneConfigurationPolicies'
        if (-not $ConfigPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No Intune Configuration Policies cached for this tenant.' -Risk $Risk -Name $Name -UserImpact $UserImpact -ImplementationEffort $ImplementationEffort -Category $Category
            return
        }

        $AsrPolicies = $ConfigPolicies | Where-Object {
            $_.platforms -like '*windows10*' -and
            $_.technologies -like '*mdm*' -and
            ($_.settings.settingInstance.settingDefinitionId -contains 'device_vendor_msft_policy_config_defender_attacksurfacereductionrules')
        }

        if (-not $AsrPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown 'No Defender Attack Surface Reduction policy is configured for Windows 10/11.' -Risk $Risk -Name $Name -UserImpact $UserImpact -ImplementationEffort $ImplementationEffort -Category $Category
            return
        }

        $Matching = foreach ($P in $AsrPolicies) {
            $children = $P.settings.settingInstance.groupSettingCollectionValue.children
            $found = $children | Where-Object { $_.settingDefinitionId -eq $RuleSettingId }
            $value = $found.choiceSettingValue.value
            if ($value -like '*_block' -or $value -like '*_warn') {
                [pscustomobject]@{ Policy = $P; Value = $value }
            }
        }

        if (-not $Matching) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "No ASR policy enables ``$FriendlyRule`` (in Block or Warn mode)." -Risk $Risk -Name $Name -UserImpact $UserImpact -ImplementationEffort $ImplementationEffort -Category $Category
            return
        }

        $Assigned = $Matching | Where-Object { $_.Policy.assignments -and $_.Policy.assignments.Count -gt 0 }

        if ($Assigned) {
            $Status = 'Passed'
            $Result = "ASR rule ``$FriendlyRule`` is enabled and assigned in $($Assigned.Count) policy/policies."
        } else {
            $Status = 'Failed'
            $Result = "ASR rule ``$FriendlyRule`` is configured but not assigned to any group/device."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk $Risk -Name $Name -UserImpact $UserImpact -ImplementationEffort $ImplementationEffort -Category $Category
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk $Risk -Name $Name -UserImpact $UserImpact -ImplementationEffort $ImplementationEffort -Category $Category
    }
}
