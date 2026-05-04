function Invoke-CippTestCIS_8_5_6 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.6) - Only organizers and co-organizers SHALL be able to present
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_6' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name 'Only organizers and co-organizers can present' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1

        if ($Cfg.DesignatedPresenterRoleMode -eq 'OrganizerOnlyUserOverride') {
            $Status = 'Passed'
            $Result = 'Only organizers / co-organizers can present.'
        } else {
            $Status = 'Failed'
            $Result = "Anyone can present by default (DesignatedPresenterRoleMode: $($Cfg.DesignatedPresenterRoleMode)). Set to OrganizerOnlyUserOverride."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_6' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Only organizers and co-organizers can present' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_6' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Only organizers and co-organizers can present' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
