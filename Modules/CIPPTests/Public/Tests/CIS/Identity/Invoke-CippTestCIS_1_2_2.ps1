function Invoke-CippTestCIS_1_2_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.2.2) - Sign-in to shared mailboxes SHALL be blocked
    #>
    param($Tenant)

    try {
        $Mailboxes = Get-CIPPTestData -TenantFilter $Tenant -Type 'Mailboxes'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Mailboxes -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_2_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Mailboxes or Users) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Sign-in to shared mailboxes is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
            return
        }

        $SharedMailboxes = $Mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'SharedMailbox' }

        if (-not $SharedMailboxes -or $SharedMailboxes.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_2_2' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No shared mailboxes found.' -Risk 'High' -Name 'Sign-in to shared mailboxes is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
            return
        }

        $EnabledShared = @()
        foreach ($SM in $SharedMailboxes) {
            $User = $Users | Where-Object { $_.userPrincipalName -eq $SM.UserPrincipalName -or $_.id -eq $SM.ExternalDirectoryObjectId } | Select-Object -First 1
            if ($User -and $User.accountEnabled -eq $true) {
                $EnabledShared += $User
            }
        }

        if ($EnabledShared.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($SharedMailboxes.Count) shared mailbox account(s) have sign-in blocked."
        } else {
            $Status = 'Failed'
            $Result = "$($EnabledShared.Count) of $($SharedMailboxes.Count) shared mailbox(es) have sign-in enabled:`n`n"
            $Result += ($EnabledShared | Select-Object -First 25 | ForEach-Object { "- $($_.userPrincipalName)" }) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_2_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Sign-in to shared mailboxes is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_2_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Sign-in to shared mailboxes is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
    }
}
