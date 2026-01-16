function Invoke-CippTestEIDSCACR03 {
    <#
    .SYNOPSIS
    Admin Consent - Reminders
    #>
    param($Tenant)

    try {
        $AdminConsentPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AdminConsentRequestPolicy'

        if (-not $AdminConsentPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR03' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Admin Consent - Reminders' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
            return
        }

        if ($AdminConsentPolicy.remindersEnabled -eq $true) {
            $Status = 'Passed'
            $Result = 'Admin consent request reminders are enabled'
        } else {
            $Status = 'Failed'
            $Result = @"
Admin consent request reminders should be enabled to ensure timely review of pending requests.

**Current Configuration:**
- remindersEnabled: $($AdminConsentPolicy.remindersEnabled)

**Recommended Configuration:**
- remindersEnabled: true

Enabling reminders helps prevent consent requests from being overlooked or delayed.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR03' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Admin Consent - Reminders' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR03' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Admin Consent - Reminders' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    }
}
