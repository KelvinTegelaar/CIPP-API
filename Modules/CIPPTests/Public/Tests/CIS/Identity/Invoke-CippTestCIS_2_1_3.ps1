function Invoke-CippTestCIS_2_1_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.3) - Notifications for internal users sending malware SHALL be enabled
    #>
    param($Tenant)

    try {
        $Malware = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoMalwareFilterPolicies'

        if (-not $Malware) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoMalwareFilterPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Notifications for internal users sending malware is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Default = $Malware | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $Default) { $Default = $Malware | Select-Object -First 1 }

        $HasRecipients = $Default.EnableInternalSenderAdminNotifications -eq $true -and -not [string]::IsNullOrWhiteSpace($Default.InternalSenderAdminAddress)

        if ($HasRecipients) {
            $Status = 'Passed'
            $Result = "Internal sender admin notifications enabled on '$($Default.Identity)'. Recipient: $($Default.InternalSenderAdminAddress)."
        } else {
            $Status = 'Failed'
            $Result = "Internal sender admin notifications are not configured on '$($Default.Identity)'.`n`n- EnableInternalSenderAdminNotifications: $($Default.EnableInternalSenderAdminNotifications)`n- InternalSenderAdminAddress: '$($Default.InternalSenderAdminAddress)'"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Notifications for internal users sending malware is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Notifications for internal users sending malware is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
