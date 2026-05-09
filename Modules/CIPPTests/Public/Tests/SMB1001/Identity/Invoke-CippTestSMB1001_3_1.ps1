function Invoke-CippTestSMB1001_3_1 {
    <#
    .SYNOPSIS
    Tests SMB1001 (3.1) - Implement a backup and recovery strategy for important digital assets

    .DESCRIPTION
    Verifies the M365 data preservation feature most relevant to recovery — Litigation Hold
    on user mailboxes — is enabled where licensed. SMB1001 3.1 also requires offline isolated
    backups; that requirement is met by a third-party M365 backup product and must be
    evidenced separately.
    #>
    param($Tenant)

    $TestId = 'SMB1001_3_1'
    $Name = 'Backup and recovery strategy preserves important digital data'

    try {
        $Mailboxes = Get-CIPPTestData -TenantFilter $Tenant -Type 'Mailboxes'

        if (-not $Mailboxes) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Mailboxes cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Data Protection'
            return
        }

        $UserMailboxes = @($Mailboxes | Where-Object { $_.recipientTypeDetails -eq 'UserMailbox' -and $_.LicensedForLitigationHold -eq $true })
        $WithoutHold = @($UserMailboxes | Where-Object { $_.LitigationHoldEnabled -ne $true })

        if ($UserMailboxes.Count -eq 0) {
            $Status = 'Informational'
            $Result = 'No user mailboxes with a licence that supports Litigation Hold were found. SMB1001 (3.1) still requires an offline-isolated backup strategy — evidence the third-party backup product separately.'
        } elseif ($WithoutHold.Count -eq 0) {
            $Status = 'Passed'
            $Result = "Litigation Hold is enabled on all $($UserMailboxes.Count) eligible user mailbox(es). Evidence the offline-isolated backup half of SMB1001 (3.1) separately (e.g., third-party M365 backup vendor)."
        } else {
            $Status = 'Failed'
            $TableRows = foreach ($M in ($WithoutHold | Select-Object -First 25)) { "- $($M.UPN)" }
            $Result = "$($WithoutHold.Count) of $($UserMailboxes.Count) eligible user mailbox(es) do not have Litigation Hold enabled. Without preservation, deleted email cannot be recovered after the retention window:`n`n$(($TableRows) -join "`n")"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Data Protection'
    }
}
