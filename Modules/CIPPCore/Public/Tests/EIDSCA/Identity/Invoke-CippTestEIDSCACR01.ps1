function Invoke-CippTestEIDSCACR01 {
    <#
    .SYNOPSIS
    Admin Consent - Enabled
    #>
    param($Tenant)

    try {
        $AdminConsentPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AdminConsentRequestPolicy'

        if (-not $AdminConsentPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Admin Consent - Enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
            return
        }

        if ($AdminConsentPolicy.isEnabled -eq $true) {
            $Status = 'Passed'
            $Result = 'Admin consent request workflow is enabled'
        } else {
            $Status = 'Failed'
            $Result = @"
Admin consent request workflow should be enabled to allow users to request administrator approval for applications.

**Current Configuration:**
- isEnabled: $($AdminConsentPolicy.isEnabled)

**Recommended Configuration:**
- isEnabled: true

Enabling this workflow provides a secure process for users to request access to applications requiring admin consent.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Admin Consent - Enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACR01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Admin Consent - Enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    }
}
