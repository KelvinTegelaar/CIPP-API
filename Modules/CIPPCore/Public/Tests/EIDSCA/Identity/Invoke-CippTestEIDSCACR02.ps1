function Invoke-CippTestEIDSCACR02 {
    <#
    .SYNOPSIS
    Admin Consent - Notify Reviewers
    #>
    param($Tenant)

    try {
        $AdminConsentPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AdminConsentRequestPolicy'

        if (-not $AdminConsentPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR02' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Admin Consent - Notify Reviewers' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
            return
        }

        if ($AdminConsentPolicy.notifyReviewers -eq $true) {
            $Status = 'Passed'
            $Result = 'Admin consent reviewers are notified of new requests'
        } else {
            $Status = 'Failed'
            $Result = @"
Admin consent reviewers should be notified when new consent requests are submitted.

**Current Configuration:**
- notifyReviewers: $($AdminConsentPolicy.notifyReviewers)

**Recommended Configuration:**
- notifyReviewers: true

Enabling notifications ensures reviewers are promptly informed of pending consent requests.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR02' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Admin Consent - Notify Reviewers' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR02' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Admin Consent - Notify Reviewers' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    }
}
