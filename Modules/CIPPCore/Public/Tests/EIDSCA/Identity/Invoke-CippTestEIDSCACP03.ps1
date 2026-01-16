function Invoke-CippTestEIDSCACP03 {
    <#
    .SYNOPSIS
    Consent Policy Settings - Block user consent for risky apps
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP03' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Consent Policy Settings - Block user consent for risky apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Consent Policy'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'BlockUserConsentForRiskyApps' }).value

        if ($SettingValue -eq 'true') {
            $Status = 'Passed'
            $Result = 'User consent for risky apps is blocked'
        } else {
            $Status = 'Failed'
            $Result = @"
User consent for risky apps should be blocked to prevent security risks.

**Current Configuration:**
- BlockUserConsentForRiskyApps: $SettingValue

**Recommended Configuration:**
- BlockUserConsentForRiskyApps: true
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP03' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Consent Policy Settings - Block user consent for risky apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Consent Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP03' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Consent Policy Settings - Block user consent for risky apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Consent Policy'
    }
}
