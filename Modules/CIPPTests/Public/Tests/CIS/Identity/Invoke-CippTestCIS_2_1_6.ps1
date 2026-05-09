function Invoke-CippTestCIS_2_1_6 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.6) - Exchange Online Spam Policies SHALL be set to notify administrators
    #>
    param($Tenant)

    try {
        $Outbound = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedOutboundSpamFilterPolicy'

        if (-not $Outbound) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_6' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoHostedOutboundSpamFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Exchange Online Spam Policies are set to notify administrators' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Default = $Outbound | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $Default) { $Default = $Outbound | Select-Object -First 1 }

        $Compliant = $Default.NotifyOutboundSpam -eq $true -and
                     $Default.BccSuspiciousOutboundMail -eq $true -and
                     $Default.NotifyOutboundSpamRecipients -and ($Default.NotifyOutboundSpamRecipients.Count -gt 0) -and
                     $Default.BccSuspiciousOutboundAdditionalRecipients -and ($Default.BccSuspiciousOutboundAdditionalRecipients.Count -gt 0)

        if ($Compliant) {
            $Status = 'Passed'
            $Result = "Outbound spam notifications are configured on '$($Default.Identity)'. Notify recipients: $($Default.NotifyOutboundSpamRecipients -join ', ')."
        } else {
            $Status = 'Failed'
            $Result = "Outbound spam notifications are not fully configured on '$($Default.Identity)':`n`n- NotifyOutboundSpam: $($Default.NotifyOutboundSpam)`n- BccSuspiciousOutboundMail: $($Default.BccSuspiciousOutboundMail)`n- NotifyOutboundSpamRecipients: $($Default.NotifyOutboundSpamRecipients -join ', ')`n- BccSuspiciousOutboundAdditionalRecipients: $($Default.BccSuspiciousOutboundAdditionalRecipients -join ', ')"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_6' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Exchange Online Spam Policies are set to notify administrators' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_6' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Exchange Online Spam Policies are set to notify administrators' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
