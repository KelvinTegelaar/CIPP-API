function Invoke-CippTestCIS_5_1_6_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.1.6.1) - Collaboration invitations SHALL be sent to allowed domains only
    #>
    param($Tenant)

    try {
        $Cross = Get-CIPPTestData -TenantFilter $Tenant -Type 'CrossTenantAccessPolicy'
        $B2B = Get-CIPPTestData -TenantFilter $Tenant -Type 'B2BManagementPolicy'

        if (-not $Cross -and -not $B2B) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (CrossTenantAccessPolicy or B2BManagementPolicy) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Collaboration invitations are sent to allowed domains only' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External Collaboration'
            return
        }

        # Inspect B2B management policy AllowedDomains / BlockedDomains.
        # b2bManagementPolicy inherits from stsPolicy, so the settings live in definition[0] as a JSON string.
        $Cfg = $B2B | Where-Object { $_.isOrganizationDefault -eq $true } | Select-Object -First 1
        if (-not $Cfg) { $Cfg = $B2B | Select-Object -First 1 }
        if ($Cfg) {
            $Domains = $null
            if ($Cfg.definition) {
                $Definition = @($Cfg.definition)[0] | ConvertFrom-Json -ErrorAction SilentlyContinue
                $Domains = $Definition.B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy
            }
            $AllowedDomains = @($Domains.AllowedDomains)
            $BlockedDomains = @($Domains.BlockedDomains)

            $Pass = ($AllowedDomains.Count -gt 0) -or ($BlockedDomains.Count -gt 0)

            if ($Pass) {
                $Status = 'Passed'
                $Result = "B2B invitations are scoped by an allow/block list (allowed: $($AllowedDomains -join ', '); blocked: $($BlockedDomains -join ', '))."
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
