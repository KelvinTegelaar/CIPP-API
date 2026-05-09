function Invoke-CippTestCIS_1_3_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.3.3) - 'External sharing' of calendars SHALL NOT be available
    #>
    param($Tenant)

    try {
        $SharingPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSharingPolicy'

        if (-not $SharingPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoSharingPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "'External sharing' of calendars is not available" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $DefaultPolicy = $SharingPolicies | Where-Object { $_.Default -eq $true } | Select-Object -First 1
        if (-not $DefaultPolicy) { $DefaultPolicy = $SharingPolicies | Select-Object -First 1 }

        $CalendarSharing = $DefaultPolicy.Domains | Where-Object { $_ -match 'CalendarSharing' }

        if (-not $CalendarSharing -or $DefaultPolicy.Enabled -eq $false) {
            $Status = 'Passed'
            $Result = "Default sharing policy '$($DefaultPolicy.Name)' does not allow external calendar sharing (Enabled: $($DefaultPolicy.Enabled))."
        } else {
            $Status = 'Failed'
            $Result = "Default sharing policy '$($DefaultPolicy.Name)' is enabled and allows external calendar sharing.`n`n**Domains entries:**`n"
            $Result += ($DefaultPolicy.Domains | ForEach-Object { "- $_" }) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "'External sharing' of calendars is not available" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "'External sharing' of calendars is not available" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
