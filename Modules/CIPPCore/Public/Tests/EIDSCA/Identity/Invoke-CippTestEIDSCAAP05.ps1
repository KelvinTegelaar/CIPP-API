function Invoke-CippTestEIDSCAAP05 {
    <#
    .SYNOPSIS
    Authorization Policy - Email-Based Subscription Sign-up
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP05' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Authorization Policy - Email-Based Subscription Sign-up' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $AllowedToSignUp = $AuthorizationPolicy.allowedToSignUpEmailBasedSubscriptions

        if ($AllowedToSignUp -eq $false) {
            $Status = 'Passed'
            $Result = 'Email-based subscription sign-up is disabled'
        } else {
            $Status = 'Failed'
            $Result = @"
Email-based subscription sign-up should be disabled to prevent unauthorized subscriptions.

**Current Configuration:**
- allowedToSignUpEmailBasedSubscriptions: $AllowedToSignUp

**Recommended Configuration:**
- allowedToSignUpEmailBasedSubscriptions: false

Disabling email-based subscriptions helps maintain control over tenant access.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP05' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Authorization Policy - Email-Based Subscription Sign-up' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP05' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Authorization Policy - Email-Based Subscription Sign-up' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
