function Invoke-CippTestCIS_6_1_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (6.1.3) - 'AuditBypassEnabled' SHALL NOT be enabled on mailboxes
    #>
    param($Tenant)

    try {
        $Mailboxes = Get-CIPPTestData -TenantFilter $Tenant -Type 'Mailboxes'

        if (-not $Mailboxes) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Mailboxes cache not found.' -Risk 'High' -Name "'AuditBypassEnabled' is not enabled on mailboxes" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
            return
        }

        $Bypassed = $Mailboxes | Where-Object { $_.AuditBypassEnabled -eq $true }

        if (-not $Bypassed -or $Bypassed.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No mailboxes have AuditBypassEnabled set to true.'
        } else {
            $Status = 'Failed'
            $Result = "$($Bypassed.Count) mailbox(es) have audit bypass enabled:`n`n"
            $Result += ($Bypassed | Select-Object -First 25 | ForEach-Object { "- $($_.UserPrincipalName)" }) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name "'AuditBypassEnabled' is not enabled on mailboxes" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_1_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name "'AuditBypassEnabled' is not enabled on mailboxes" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'
    }
}
