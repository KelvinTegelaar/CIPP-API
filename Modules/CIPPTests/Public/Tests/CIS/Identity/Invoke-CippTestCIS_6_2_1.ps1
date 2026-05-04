function Invoke-CippTestCIS_6_2_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.2.1) - All forms of mail forwarding SHALL be blocked and/or disabled
    #>
    param($Tenant)

    try {
        $Outbound = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoHostedOutboundSpamFilterPolicy'
        $RemoteDomain = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoRemoteDomain'

        if (-not $Outbound) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoHostedOutboundSpamFilterPolicy cache not found.' -Risk 'High' -Name 'All forms of mail forwarding are blocked and/or disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Default = $Outbound | Where-Object { $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $Default) { $Default = $Outbound | Select-Object -First 1 }

        $AutoForwardOff = $Default.AutoForwardingMode -eq 'Off'

        $RemoteDefault = $RemoteDomain | Where-Object { $_.Name -eq 'Default' } | Select-Object -First 1
        $RemoteForwardOff = -not $RemoteDefault -or $RemoteDefault.AutoForwardEnabled -eq $false

        if ($AutoForwardOff -and $RemoteForwardOff) {
            $Status = 'Passed'
            $Result = "Auto-forwarding is blocked at the outbound spam filter (AutoForwardingMode: Off) and disabled on the default remote domain."
        } else {
            $Status = 'Failed'
            $Result = "Auto-forwarding is not fully blocked.`n`n- Outbound spam filter AutoForwardingMode: $($Default.AutoForwardingMode)`n- Default remote domain AutoForwardEnabled: $($RemoteDefault.AutoForwardEnabled)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'All forms of mail forwarding are blocked and/or disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_2_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'All forms of mail forwarding are blocked and/or disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
