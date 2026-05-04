function Invoke-CippTestCIS_6_5_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.5.2) - MailTips SHALL be enabled for end users
    #>
    param($Tenant)

    try {
        $Org = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $Org) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found.' -Risk 'Medium' -Name 'MailTips are enabled for end users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Cfg = $Org | Select-Object -First 1

        $Compliant = $Cfg.MailTipsAllTipsEnabled -eq $true -and
                     $Cfg.MailTipsExternalRecipientsTipsEnabled -eq $true -and
                     $Cfg.MailTipsGroupMetricsEnabled -eq $true -and
                     [int]$Cfg.MailTipsLargeAudienceThreshold -ge 1 -and [int]$Cfg.MailTipsLargeAudienceThreshold -le 25

        if ($Compliant) {
            $Status = 'Passed'
            $Result = "All MailTips are enabled (LargeAudienceThreshold: $($Cfg.MailTipsLargeAudienceThreshold))."
        } else {
            $Status = 'Failed'
            $Result = "MailTips are not fully enabled.`n`n- AllTipsEnabled: $($Cfg.MailTipsAllTipsEnabled)`n- ExternalRecipientsTipsEnabled: $($Cfg.MailTipsExternalRecipientsTipsEnabled)`n- GroupMetricsEnabled: $($Cfg.MailTipsGroupMetricsEnabled)`n- LargeAudienceThreshold: $($Cfg.MailTipsLargeAudienceThreshold)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'MailTips are enabled for end users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_5_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'MailTips are enabled for end users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
