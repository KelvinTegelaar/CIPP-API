function Invoke-CippTestCIS_8_5_7 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.7) - External participants SHALL NOT give or request control
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_7' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name "External participants can't give or request control" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1

        if ($Cfg.AllowExternalParticipantGiveRequestControl -eq $false) {
            $Status = 'Passed'
            $Result = 'External participants cannot give or request control.'
        } else {
            $Status = 'Failed'
            $Result = "External participants can give or request control (AllowExternalParticipantGiveRequestControl: $($Cfg.AllowExternalParticipantGiveRequestControl))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_7' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "External participants can't give or request control" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_7' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "External participants can't give or request control" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
