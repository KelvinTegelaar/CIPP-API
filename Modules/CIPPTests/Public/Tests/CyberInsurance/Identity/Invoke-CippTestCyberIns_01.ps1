function Invoke-CippTestCyberIns_01 {
    <#
    .SYNOPSIS
    Cyber Insurance Q1 - MFA is enforced for all email users
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_01'; TestType = 'Identity'; Risk = 'High'; Name = 'MFA is enforced for all email users'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $MFAData = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'
        if (-not $MFAData) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No MFA data found for this tenant. Sync the report data first.'
            return
        }

        $Total = 0
        $Unprotected = [System.Collections.Generic.List[string]]::new()
        foreach ($User in $MFAData) {
            if ($User.AccountEnabled -ne $true -or $User.isLicensed -ne $true -or $User.UserType -ne 'Member') { continue }
            $Total++
            if ($User.CoveredByCA -notlike 'Enforced*' -and $User.CoveredBySD -ne $true -and $User.PerUser -notin @('Enforced', 'Enabled')) {
                $Unprotected.Add([string]$User.UPN)
            }
        }

        if ($Total -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No enabled, licensed member users were found for this tenant.'
            return
        }

        $Protected = $Total - $Unprotected.Count
        $Result = [System.Text.StringBuilder]::new("MFA is enforced for **$Protected of $Total** enabled, licensed member users, through Conditional Access, Security Defaults or per-user MFA.`n`n")

        $Pop = 0; $Imap = 0; $Smtp = 0; $Mailboxes = 0
        foreach ($Mailbox in (Get-CIPPTestData -TenantFilter $Tenant -Type 'CASMailbox')) {
            $Mailboxes++
            if ($Mailbox.PopEnabled -eq $true) { $Pop++ }
            if ($Mailbox.ImapEnabled -eq $true) { $Imap++ }
            if ($Mailbox.SmtpClientAuthenticationDisabled -eq $false) { $Smtp++ }
        }
        if ($Mailboxes -gt 0) {
            $null = $Result.Append("Legacy mail protocols can bypass MFA. Of $Mailboxes mailboxes: POP is on for $Pop, IMAP is on for $Imap, and SMTP AUTH is explicitly allowed for $Smtp.`n`n")
        }

        if ($Unprotected.Count -gt 0) {
            $null = $Result.Append("Users without enforced MFA:`n`n")
            foreach ($UPN in $Unprotected.GetRange(0, [Math]::Min(25, $Unprotected.Count))) { $null = $Result.Append("- $UPN`n") }
            if ($Unprotected.Count -gt 25) { $null = $Result.Append("- and $($Unprotected.Count - 25) more`n") }
        }

        $Status = if ($Unprotected.Count -eq 0) { 'Passed' } else { 'Failed' }
        Add-CippTestResult @Meta -Status $Status -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_01: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
