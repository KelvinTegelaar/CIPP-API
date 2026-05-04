function Invoke-CippTestCIS_8_5_9 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.9) - Meeting recording SHALL be off by default
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_9' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name 'Meeting recording is off by default' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1

        if ($Cfg.AllowCloudRecording -eq $false) {
            $Status = 'Passed'
            $Result = 'Cloud recording is disabled in the global meeting policy.'
        } else {
            $Status = 'Failed'
            $Result = "Cloud recording is enabled in the global meeting policy (AllowCloudRecording: $($Cfg.AllowCloudRecording))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_9' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Meeting recording is off by default' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_9' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Meeting recording is off by default' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
