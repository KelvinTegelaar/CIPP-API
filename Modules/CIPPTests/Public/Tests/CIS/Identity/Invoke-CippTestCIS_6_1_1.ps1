function Invoke-CippTestCIS_6_1_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.1.1) - 'AuditDisabled' organizationally SHALL be 'False'
    #>
    param($Tenant)

    try {
        $Org = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $Org) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found.' -Risk 'High' -Name "'AuditDisabled' organizationally is set to 'False'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
            return
        }

        $Cfg = $Org | Select-Object -First 1

        if ($Cfg.AuditDisabled -eq $false) {
            $Status = 'Passed'
            $Result = 'Mailbox auditing is enabled organisation-wide (AuditDisabled: false).'
        } else {
            $Status = 'Failed'
            $Result = "Mailbox auditing is disabled organisation-wide (AuditDisabled: $($Cfg.AuditDisabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name "'AuditDisabled' organizationally is set to 'False'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name "'AuditDisabled' organizationally is set to 'False'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    }
}
