function Invoke-CippTestEIDSCACR04 {
    <#
    .SYNOPSIS
    Admin Consent - Duration
    #>
    param($Tenant)

    try {
        $AdminConsentPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AdminConsentRequestPolicy'

        if (-not $AdminConsentPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR04' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Admin Consent - Duration' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
            return
        }

        $RequestDuration = $AdminConsentPolicy.requestDurationInDays

        if ($RequestDuration -le 30) {
            $Status = 'Passed'
            $Result = "Admin consent request duration is set to $RequestDuration days (30 days or less)"
        } else {
            $Status = 'Failed'
            $Result = @"
Admin consent request duration should be set to 30 days or less to ensure timely review.

**Current Configuration:**
- requestDurationInDays: $RequestDuration

**Recommended Configuration:**
- requestDurationInDays: 30 or less

A shorter duration ensures consent requests are reviewed and processed in a timely manner.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR04' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Admin Consent - Duration' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR04' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Admin Consent - Duration' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    }
}
