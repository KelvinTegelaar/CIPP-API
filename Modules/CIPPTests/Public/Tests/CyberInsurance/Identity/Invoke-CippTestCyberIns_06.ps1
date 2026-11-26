function Invoke-CippTestCyberIns_06 {
    <#
    .SYNOPSIS
    Cyber Insurance Q6 - Admin accounts are separate from daily-use accounts
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_06'; TestType = 'Identity'; Risk = 'High'; Name = 'Admin accounts are separate from daily-use accounts'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $MFAData = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'
        if (-not $MFAData) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No user data found for this tenant. Sync the report data first.'
            return
        }

        $MailboxUpns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Mailbox in (Get-CIPPTestData -TenantFilter $Tenant -Type 'Mailboxes')) {
            if ($Mailbox.recipientTypeDetails -eq 'UserMailbox' -and $Mailbox.UPN) { $null = $MailboxUpns.Add([string]$Mailbox.UPN) }
        }

        $Total = 0
        $DualUse = [System.Collections.Generic.List[string]]::new()
        foreach ($User in $MFAData) {
            if ($User.IsAdmin -ne $true -or $User.AccountEnabled -ne $true) { continue }
            $Total++
            $HasMailbox = $MailboxUpns.Contains([string]$User.UPN)
            if ($User.isLicensed -eq $true -or $HasMailbox) {
                $Reason = if ($HasMailbox) { 'has a mailbox' } else { 'holds a licence' }
                $DualUse.Add("$($User.UPN) ($Reason)")
            }
        }

        if ($Total -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No enabled accounts holding a directory role were found for this tenant.'
            return
        }

        if ($DualUse.Count -eq 0) {
            Add-CippTestResult @Meta -Status 'Passed' -ResultMarkdown "None of the $Total enabled accounts that hold a directory role has a mailbox or a licence."
            return
        }

        $Result = [System.Text.StringBuilder]::new("**$($DualUse.Count) of $Total** enabled accounts that hold a directory role also have a mailbox or a licence, which suggests they are used for daily work:`n`n")
        foreach ($Entry in $DualUse) { $null = $Result.Append("- $Entry`n") }
        Add-CippTestResult @Meta -Status 'Investigate' -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_06: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
