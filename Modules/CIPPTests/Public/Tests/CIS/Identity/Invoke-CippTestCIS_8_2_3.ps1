function Invoke-CippTestCIS_8_2_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.2.3) - External Teams users SHALL NOT be able to initiate conversations
    #>
    param($Tenant)

    try {
        $Messaging = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMessagingPolicy'

        if (-not $Messaging) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMessagingPolicy cache not found.' -Risk 'High' -Name 'External Teams users cannot initiate conversations' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $Messaging | Select-Object -First 1

        if ($Cfg.UseB2BInvitesToAddExternalUsers -eq $false) {
            $Status = 'Passed'
            $Result = 'External users cannot initiate Teams chats via email (UseB2BInvitesToAddExternalUsers: false).'
        } else {
            $Status = 'Failed'
            $Result = "External users can initiate Teams chats via email (UseB2BInvitesToAddExternalUsers: $($Cfg.UseB2BInvitesToAddExternalUsers))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'External Teams users cannot initiate conversations' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'External Teams users cannot initiate conversations' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
