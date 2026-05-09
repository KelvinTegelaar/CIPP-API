function Invoke-CippTestCIS_8_5_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.3) - Only people in my org SHALL be able to bypass the lobby
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name 'Only people in my org can bypass the lobby' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1
        $Acceptable = @('OrganizerOnly', 'EveryoneInCompanyExcludingGuests', 'InvitedUsers')

        if ($Cfg.AutoAdmittedUsers -in $Acceptable) {
            $Status = 'Passed'
            $Result = "Lobby bypass restricted (AutoAdmittedUsers: $($Cfg.AutoAdmittedUsers))."
        } else {
            $Status = 'Failed'
            $Result = "Lobby bypass too permissive (AutoAdmittedUsers: $($Cfg.AutoAdmittedUsers)). Set to EveryoneInCompanyExcludingGuests or stricter."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Only people in my org can bypass the lobby' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Only people in my org can bypass the lobby' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
