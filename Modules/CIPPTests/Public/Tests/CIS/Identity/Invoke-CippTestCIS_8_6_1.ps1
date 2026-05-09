function Invoke-CippTestCIS_8_6_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.6.1) - Users SHALL be able to report security concerns in Teams
    #>
    param($Tenant)

    try {
        $Messaging = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMessagingPolicy'
        $Submission = Get-CIPPTestData -TenantFilter $Tenant -Type 'ReportSubmissionPolicy'

        if (-not $Messaging -or -not $Submission) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_6_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (CsTeamsMessagingPolicy or ReportSubmissionPolicy) not found.' -Risk 'Medium' -Name 'Users can report security concerns in Teams' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Reporting'
            return
        }

        $M = $Messaging | Select-Object -First 1
        $S = $Submission | Select-Object -First 1

        $TeamsReporting = $M.AllowSecurityEndUserReporting -eq $true
        $DefenderReporting = ($S.ReportJunkToCustomizedAddress -eq $true -or $S.ReportPhishToCustomizedAddress -eq $true) -and
                            ($S.ReportChatMessageEnabled -eq $true -or $S.ReportChatMessageToCustomizedAddressEnabled -eq $true)

        if ($TeamsReporting -and $DefenderReporting) {
            $Status = 'Passed'
            $Result = "Teams security reporting is enabled and routed to a monitored mailbox.`n`n- AllowSecurityEndUserReporting: $($M.AllowSecurityEndUserReporting)`n- ReportChatMessageEnabled: $($S.ReportChatMessageEnabled)`n- ReportChatMessageToCustomizedAddressEnabled: $($S.ReportChatMessageToCustomizedAddressEnabled)"
        } else {
            $Status = 'Failed'
            $Result = "Teams security reporting is not fully configured.`n`n- AllowSecurityEndUserReporting: $($M.AllowSecurityEndUserReporting)`n- ReportJunkToCustomizedAddress: $($S.ReportJunkToCustomizedAddress)`n- ReportPhishToCustomizedAddress: $($S.ReportPhishToCustomizedAddress)`n- ReportChatMessageEnabled: $($S.ReportChatMessageEnabled)`n- ReportChatMessageToCustomizedAddressEnabled: $($S.ReportChatMessageToCustomizedAddressEnabled)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_6_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users can report security concerns in Teams' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Reporting'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_6_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users can report security concerns in Teams' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Reporting'
    }
}
