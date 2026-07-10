function Invoke-CippTestE8_Backup_01 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Regular Backups, ML1) - User mailboxes have litigation hold or retention applied
    #>
    param($Tenant)

    $TestId = 'E8_Backup_01'
    $Name = 'User mailboxes have litigation hold or a retention policy applied'

    try {
        $Mailboxes = Get-CIPPTestData -TenantFilter $Tenant -Type 'Mailboxes'
        if (-not $Mailboxes) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No Mailboxes cached for this tenant.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Regular Backups'
            return
        }

        # Inactive (soft-deleted) mailboxes carry WhenSoftDeleted; there is no IsInactiveMailbox field in the cache.
        $UserMailboxes = $Mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'UserMailbox' -and -not $_.WhenSoftDeleted }
        if (-not $UserMailboxes) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No user mailboxes found.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Regular Backups'
            return
        }

        # The built-in "Default MRM Policy" is present on every mailbox and only manages archive/deletion tags —
        # it is not a data-protection retention control, so it does not count as protected.
        $Unprotected = $UserMailboxes | Where-Object {
            -not ($_.LitigationHoldEnabled -eq $true) -and
            -not ($_.ComplianceTagHoldApplied -eq $true) -and
            ([string]::IsNullOrWhiteSpace($_.RetentionPolicy) -or $_.RetentionPolicy -eq 'Default MRM Policy') -and
            -not $_.InPlaceHolds
        }

        if (-not $Unprotected) {
            $Status = 'Passed'
            $Result = "All $($UserMailboxes.Count) user mailbox(es) have at least one of: litigation hold, a non-default retention policy, or compliance hold applied."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($Unprotected.Count) of $($UserMailboxes.Count) user mailbox(es) have no litigation hold, retention policy, or compliance tag applied:`n`n| UPN |`n| :-- |`n")
            foreach ($M in ($Unprotected | Select-Object -First 50)) { $null = $Sb.Append("| $($M.UPN) |`n") }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Regular Backups'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Regular Backups'
    }
}
