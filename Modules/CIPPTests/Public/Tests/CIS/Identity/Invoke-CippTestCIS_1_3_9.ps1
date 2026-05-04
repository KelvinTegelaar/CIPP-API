function Invoke-CippTestCIS_1_3_9 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.3.9) - Shared bookings pages SHALL be restricted to select users
    #>
    param($Tenant)

    try {
        $OrgConfig = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $OrgConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_9' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Shared bookings pages are restricted to select users' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Data Protection'
            return
        }

        $Cfg = $OrgConfig | Select-Object -First 1

        if ($Cfg.BookingsEnabled -eq $false) {
            $Status = 'Passed'
            $Result = 'Bookings is disabled at the organisation level (BookingsEnabled: false) — a more restrictive and compliant configuration.'
        } else {
            $Status = 'Failed'
            $Result = "Bookings is enabled at the organisation level (BookingsEnabled: true). Either disable it organisation-wide, or set BookingsMailboxCreationEnabled = $false on the default OWA mailbox policy and assign Bookings access to specific users via a separate policy."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_9' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Shared bookings pages are restricted to select users' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_9' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Shared bookings pages are restricted to select users' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Data Protection'
    }
}
