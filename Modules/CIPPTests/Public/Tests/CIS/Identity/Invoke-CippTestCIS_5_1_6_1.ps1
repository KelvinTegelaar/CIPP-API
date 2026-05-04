function Invoke-CippTestCIS_5_1_6_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.6.1) - Collaboration invitations SHALL be sent to allowed domains only
    #>
    param($Tenant)

    try {
        $Cross = Get-CIPPTestData -TenantFilter $Tenant -Type 'CrossTenantAccessPolicy'
        $B2B = Get-CIPPTestData -TenantFilter $Tenant -Type 'B2BManagementPolicy'

        if (-not $Cross -and -not $B2B) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (CrossTenantAccessPolicy or B2BManagementPolicy) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Collaboration invitations are sent to allowed domains only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
            return
        }

        # Inspect B2B management policy AllowedDomains / BlockedDomains
        $Cfg = $B2B | Select-Object -First 1
        if ($Cfg) {
            $Allowed = $Cfg.allowInvitesFrom
            $Domains = $Cfg.invitationsAllowedAndBlockedDomainsPolicy

            $Pass = $Domains -and (
                ($Domains.allowedDomains -and $Domains.allowedDomains.Count -gt 0) -or
                ($Domains.blockedDomains -and $Domains.blockedDomains.Count -gt 0)
            )

            if ($Pass) {
                $Status = 'Passed'
                $Result = "B2B invitations are scoped by an allow/block list (allowed: $($Domains.allowedDomains -join ', '); blocked: $($Domains.blockedDomains -join ', '))."
            } else {
                $Status = 'Failed'
                $Result = 'B2B invitations are not constrained by an allow / block list. Configure invitationsAllowedAndBlockedDomainsPolicy.'
            }
        } else {
            $Status = 'Failed'
            $Result = 'No B2B management policy with domain restrictions was found.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Collaboration invitations are sent to allowed domains only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Collaboration invitations are sent to allowed domains only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
    }
}
