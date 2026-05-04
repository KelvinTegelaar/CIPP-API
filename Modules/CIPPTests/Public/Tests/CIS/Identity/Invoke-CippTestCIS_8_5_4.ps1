function Invoke-CippTestCIS_8_5_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.4) - Users dialing in SHALL NOT bypass the lobby
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name "Users dialing in can't bypass the lobby" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1

        if ($Cfg.AllowPSTNUsersToBypassLobby -eq $false) {
            $Status = 'Passed'
            $Result = 'Dial-in users cannot bypass the lobby (AllowPSTNUsersToBypassLobby: false).'
        } else {
            $Status = 'Failed'
            $Result = "Dial-in users can bypass the lobby (AllowPSTNUsersToBypassLobby: $($Cfg.AllowPSTNUsersToBypassLobby))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "Users dialing in can't bypass the lobby" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Users dialing in can't bypass the lobby" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
