function Invoke-CippTestCIS_8_5_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.2) - Anonymous users and dial-in callers SHALL NOT be able to start a meeting
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name "Anonymous users and dial-in callers can't start a meeting" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1

        if ($Cfg.AllowAnonymousUsersToStartMeeting -eq $false) {
            $Status = 'Passed'
            $Result = 'Anonymous users cannot start meetings (AllowAnonymousUsersToStartMeeting: false).'
        } else {
            $Status = 'Failed'
            $Result = "Anonymous users can start meetings (AllowAnonymousUsersToStartMeeting: $($Cfg.AllowAnonymousUsersToStartMeeting))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "Anonymous users and dial-in callers can't start a meeting" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Anonymous users and dial-in callers can't start a meeting" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
