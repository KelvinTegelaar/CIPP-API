function Invoke-CippTestCISAMSEXO51 {
    <#
    .SYNOPSIS
    Tests MS.EXO.5.1 - SMTP AUTH SHALL be disabled for all users

    .DESCRIPTION
    Checks if SMTP authentication is disabled in CAS Mailbox settings

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $CASMailboxes = New-CIPPDbRequest -TenantFilter $Tenant -Type 'CASMailbox'

        if (-not $CASMailboxes) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'CASMailbox cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'SMTP AUTH SHALL be disabled in Exchange Online' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Authentication' -TestId 'CISAMSEXO51' -TenantFilter $Tenant
            return
        }

        $FailedMailboxes = $CASMailboxes | Where-Object { $_.SmtpClientAuthenticationDisabled -eq $false }

        if ($FailedMailboxes.Count -eq 0) {
            $Result = "✅ **Pass**: SMTP authentication is disabled for all $($CASMailboxes.Count) mailbox(es)."
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: $($FailedMailboxes.Count) of $($CASMailboxes.Count) mailbox(es) have SMTP authentication enabled"
            if ($FailedMailboxes.Count -gt 10) {
                $Result += ' (showing first 10)'
            }
            $Result += ":`n`n"
            $Result += "| Display Name | Identity | SMTP Auth Disabled |`n"
            $Result += "| :----------- | :------- | :----------------- |`n"
            foreach ($Mailbox in ($FailedMailboxes | Select-Object -First 10)) {
                $Result += "| $($Mailbox.DisplayName) | $($Mailbox.Identity) | $($Mailbox.SmtpClientAuthenticationDisabled) |`n"
            }
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO51' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SMTP AUTH SHALL be disabled in Exchange Online' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Authentication'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SMTP AUTH SHALL be disabled in Exchange Online' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Email Authentication' -TestId 'CISAMSEXO51' -TenantFilter $Tenant
    }
}
