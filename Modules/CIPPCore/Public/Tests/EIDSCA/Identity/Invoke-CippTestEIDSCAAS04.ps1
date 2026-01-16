function Invoke-CippTestEIDSCAAS04 {
    <#
    .SYNOPSIS
    SMS - No Sign-In
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAS04' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'SMS - No Sign-In' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $SmsConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Sms' }

        if (-not $SmsConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAS04' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'SMS authentication configuration not found in Authentication Methods Policy.' -Risk 'High' -Name 'SMS - No Sign-In' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $InvalidTargets = @()
        if ($SmsConfig.includeTargets) {
            foreach ($target in $SmsConfig.includeTargets) {
                if ($target.isUsableForSignIn -ne $false) {
                    $InvalidTargets += $target.id
                }
            }
        }

        if ($InvalidTargets.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'SMS authentication is not allowed for sign-in on any targets'
        } else {
            $Status = 'Failed'
            $Result = @"
SMS should not be allowed for sign-in as it is vulnerable to SIM swap and interception attacks. SMS should only be used for MFA verification, not primary authentication.

**Current Configuration:**
- Targets with sign-in enabled: $($InvalidTargets.Count)

**Recommended Configuration:**
- All includeTargets should have isUsableForSignIn: false

Disabling SMS for sign-in while keeping it for MFA provides better security.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAS04' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'SMS - No Sign-In' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAS04' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'SMS - No Sign-In' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
