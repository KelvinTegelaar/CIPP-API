function Invoke-CippTestCIS_2_1_15 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.15) - Outbound anti-spam message limits SHALL be in place
    #>
    param($Tenant)

    try {
        $Outbound = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedOutboundSpamFilterPolicy'

        if (-not $Outbound) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_15' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoHostedOutboundSpamFilterPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Outbound anti-spam message limits are in place' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
            return
        }

        $Default = $Outbound | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $Default) { $Default = $Outbound | Select-Object -First 1 }

        $External = [int]$Default.RecipientLimitExternalPerHour
        $Internal = [int]$Default.RecipientLimitInternalPerHour
        $Daily    = [int]$Default.RecipientLimitPerDay
        $Action   = $Default.ActionWhenThresholdReached

        $Pass = $External -gt 0 -and $External -le 500 -and
                $Internal -gt 0 -and $Internal -le 1000 -and
                $Daily -gt 0 -and $Daily -le 1000 -and
                $Action -in @('BlockUser', 'BlockUserForToday')

        if ($Pass) {
            $Status = 'Passed'
            $Result = "Outbound anti-spam limits are within CIS recommendations on '$($Default.Identity)'.`n`n- External/hr: $External`n- Internal/hr: $Internal`n- Daily: $Daily`n- Action: $Action"
        } else {
            $Status = 'Failed'
            $Result = "Outbound limits on '$($Default.Identity)' do not meet CIS recommended values (External<=500/hr, Internal<=1000/hr, Daily<=1000, Action=BlockUser):`n`n- External/hr: $External`n- Internal/hr: $Internal`n- Daily: $Daily`n- Action: $Action"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_15' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Outbound anti-spam message limits are in place' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_15' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Outbound anti-spam message limits are in place' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'
    }
}
