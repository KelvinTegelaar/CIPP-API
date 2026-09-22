function Invoke-CippTestCIS_6_1_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (6.1.2) - Mailbox audit actions SHALL be configured
    #>
    param($Tenant)

    try {
        $Mailboxes = Get-CIPPTestData -TenantFilter $Tenant -Type 'Mailboxes'

        if (-not $Mailboxes) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Mailboxes cache not found.' -Risk 'High' -Name 'Mailbox audit actions are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
            return
        }

        $User = $Mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'UserMailbox' }
        # CIS 6.1.2 requires per-mailbox audit ACTIONS to be configured. With mailbox auditing on by
        # default Microsoft applies the default action sets and Get-Mailbox reports AuditEnabled = True,
        # so the reliable signal is a non-empty AuditOwner (the effective owner actions) or a
        # DefaultAuditSet that still lists the Owner sign-in type (Microsoft-managed defaults).
        # AuditEnabled itself can arrive as a string from EXO REST and is not graded directly.
        $Failures = $User | Where-Object {
            @($_.AuditOwner).Count -eq 0 -and ("$($_.DefaultAuditSet)" -notmatch 'Owner')
        }

        if ($Failures.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($User.Count) user mailbox(es) have owner audit actions configured."
        } else {
            $Status = 'Failed'
            $Result = "$($Failures.Count) of $($User.Count) user mailbox(es) have no owner audit actions configured."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Mailbox audit actions are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Mailbox audit actions are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    }
}
