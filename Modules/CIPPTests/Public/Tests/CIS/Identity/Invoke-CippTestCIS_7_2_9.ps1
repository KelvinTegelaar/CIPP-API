function Invoke-CippTestCIS_7_2_9 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.9) - Guest access to a site or OneDrive SHALL expire automatically
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_9' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Guest access to a site or OneDrive will expire automatically' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1
        $Required = $Cfg.ExternalUserExpirationRequired
        $Days = [int]$Cfg.ExternalUserExpireInDays

        if ($Required -eq $true -and $Days -gt 0 -and $Days -le 30) {
            $Status = 'Passed'
            $Result = "External user expiration is enforced after $Days days."
        } else {
            $Status = 'Failed'
            $Result = "External user expiration is not enforced (ExternalUserExpirationRequired: $Required, ExternalUserExpireInDays: $Days). CIS recommends 30 or less."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_9' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Guest access to a site or OneDrive will expire automatically' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_9' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guest access to a site or OneDrive will expire automatically' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
