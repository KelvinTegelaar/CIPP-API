function Invoke-CippTestCIS_6_1_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.1.2) - Mailbox audit actions SHALL be configured
    #>
    param($Tenant)

    try {
        $Mailboxes = Get-CIPPTestData -TenantFilter $Tenant -Type 'Mailboxes'

        if (-not $Mailboxes) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Mailboxes cache not found.' -Risk 'High' -Name 'Mailbox audit actions are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
            return
        }

        $User = $Mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'UserMailbox' }
        $Failures = $User | Where-Object { $_.AuditEnabled -eq $false -or -not $_.AuditOwner -or $_.AuditOwner.Count -eq 0 }

        if ($Failures.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($User.Count) user mailbox(es) have auditing enabled with audit actions configured."
        } else {
            $Status = 'Failed'
            $Result = "$($Failures.Count) of $($User.Count) user mailbox(es) have auditing disabled or no audit actions configured."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Mailbox audit actions are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Mailbox audit actions are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    }
}
