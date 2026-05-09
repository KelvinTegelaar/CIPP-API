function Invoke-CippTestCIS_8_5_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.5) - Meeting chat SHALL NOT allow anonymous users
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name 'Meeting chat does not allow anonymous users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1
        $Acceptable = @('EnabledExceptAnonymous', 'Disabled')

        if ($Cfg.MeetingChatEnabledType -in $Acceptable) {
            $Status = 'Passed'
            $Result = "Anonymous users cannot use meeting chat (MeetingChatEnabledType: $($Cfg.MeetingChatEnabledType))."
        } else {
            $Status = 'Failed'
            $Result = "Anonymous users can use meeting chat (MeetingChatEnabledType: $($Cfg.MeetingChatEnabledType)). Set to EnabledExceptAnonymous."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Meeting chat does not allow anonymous users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Meeting chat does not allow anonymous users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
