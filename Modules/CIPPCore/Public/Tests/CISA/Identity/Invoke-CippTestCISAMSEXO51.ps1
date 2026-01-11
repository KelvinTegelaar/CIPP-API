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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'CASMailbox cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO51' -TenantFilter $Tenant
            return
        }

        $FailedMailboxes = $CASMailboxes | Where-Object { $_.SmtpClientAuthenticationDisabled -eq $false }

        if ($FailedMailboxes.Count -eq 0) {
            $Result = "✅ **Pass**: SMTP authentication is disabled for all $($CASMailboxes.Count) mailbox(es)."
            $Status = 'Pass'
        } else {
            $ResultTable = $FailedMailboxes | Select-Object -First 10 | ForEach-Object {
                [PSCustomObject]@{
                    'Display Name'       = $_.DisplayName
                    'Identity'           = $_.Identity
                    'SMTP Auth Disabled' = $_.SmtpClientAuthenticationDisabled
                }
            }

            $Result = "❌ **Fail**: $($FailedMailboxes.Count) of $($CASMailboxes.Count) mailbox(es) have SMTP authentication enabled"
            if ($FailedMailboxes.Count -gt 10) {
                $Result += ' (showing first 10)'
            }
            $Result += ":`n`n"
            $Result += ($ResultTable | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO51' -Status $Status -ResultMarkdown $Result -Risk 'High' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO51' -TenantFilter $Tenant
    }
}
function Invoke-CippTestCISAMSEXO51 {
    <#
    .SYNOPSIS
    MS.EXO.5.1 - SMTP authentication SHALL be disabled

    .DESCRIPTION
    Tests if SMTP AUTH is disabled in Exchange Online organization config

    .LINK
    https://github.com/cisagov/ScubaGear
    #>
    param($Tenant)

    try {
        $OrgConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $OrgConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO51' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please ensure cache data is available.' -Risk 'High' -Name 'SMTP authentication disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
            return
        }

        $SmtpAuthDisabled = $OrgConfig.SmtpClientAuthenticationDisabled

        if ($SmtpAuthDisabled -eq $true) {
            $Status = 'Passed'
            $Result = "✅ Well done. Your tenant has SMTP Authentication disabled organization-wide.`n`n"
            $Result += "**Current Configuration:**`n"
            $Result += "- SMTP Client Authentication: **Disabled** ✅`n"
        } else {
            $Status = 'Failed'
            $Result = "❌ Your tenant has SMTP Authentication enabled.`n`n"
            $Result += "**Current Configuration:**`n"
            $Result += "- SMTP Client Authentication: **Enabled** ❌`n`n"
            $Result += "**Recommendation:** Disable SMTP AUTH to prevent legacy authentication attacks. Users should use modern authentication methods.`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO51' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SMTP authentication disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run CISA test CISAMSEXO51: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO51' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SMTP authentication disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
    }
}
function Invoke-CippTestCISAMSEXO51 {
    <#
    .SYNOPSIS
    MS.EXO.5.1 - SMTP authentication SHALL be disabled
    
    .DESCRIPTION
    Tests if SMTP AUTH is disabled in Exchange Online organization config
    
    .LINK
    https://github.com/cisagov/ScubaGear
    #>
    param($Tenant)
    
    try {
        $OrgConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoOrganizationConfig'
        
        if (-not $OrgConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO51' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please ensure cache data is available.' -Risk 'High' -Name 'SMTP authentication disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
            return
        }
        
        $SmtpAuthDisabled = $OrgConfig.SmtpClientAuthenticationDisabled
        
        if ($SmtpAuthDisabled -eq $true) {
            $Status = 'Passed'
            $Result = "✅ Well done. Your tenant has SMTP Authentication disabled organization-wide.`n`n"
            $Result += "**Current Configuration:**`n"
            $Result += "- SMTP Client Authentication: **Disabled** ✅`n"
        } else {
            $Status = 'Failed'
            $Result = "❌ Your tenant has SMTP Authentication enabled.`n`n"
            $Result += "**Current Configuration:**`n"
            $Result += "- SMTP Client Authentication: **Enabled** ❌`n`n"
            $Result += "**Recommendation:** Disable SMTP AUTH to prevent legacy authentication attacks. Users should use modern authentication methods.`n"
        }
        
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO51' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SMTP authentication disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run CISA test CISAMSEXO51: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO51' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SMTP authentication disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Exchange Online'
    }
}
