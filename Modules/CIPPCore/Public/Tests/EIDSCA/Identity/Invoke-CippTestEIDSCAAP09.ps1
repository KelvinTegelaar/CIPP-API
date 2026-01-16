function Invoke-CippTestEIDSCAAP09 {
    <#
    .SYNOPSIS
    Authorization Policy - Consent for Risky Apps
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP09' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Authorization Policy - Consent for Risky Apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $AllowConsentRiskyApps = $AuthorizationPolicy.allowUserConsentForRiskyApps

        if ($AllowConsentRiskyApps -eq $false) {
            $Status = 'Passed'
            $Result = 'User consent for risky apps is disabled'
        } else {
            $Status = 'Failed'
            $Result = @"
User consent for risk-based apps should be disabled to prevent users from consenting to potentially malicious applications.

**Current Configuration:**
- allowUserConsentForRiskyApps: $AllowConsentRiskyApps

**Recommended Configuration:**
- allowUserConsentForRiskyApps: false

Disabling this prevents users from consenting to apps identified as risky.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP09' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Authorization Policy - Consent for Risky Apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP09' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Authorization Policy - Consent for Risky Apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
