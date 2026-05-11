function Invoke-CippTestCIS_8_5_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.1) - Anonymous users SHALL NOT be able to join a meeting
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name "Anonymous users can't join a meeting" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1

        if ($Cfg.AllowAnonymousUsersToJoinMeeting -eq $false) {
            $Status = 'Passed'
            $Result = 'Anonymous users cannot join meetings (AllowAnonymousUsersToJoinMeeting: false).'
        } else {
            $Status = 'Failed'
            $Result = "Anonymous users can join meetings (AllowAnonymousUsersToJoinMeeting: $($Cfg.AllowAnonymousUsersToJoinMeeting))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "Anonymous users can't join a meeting" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Anonymous users can't join a meeting" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
