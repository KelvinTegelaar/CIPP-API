function Invoke-CippTestEIDSCAAT01 {
    <#
    .SYNOPSIS
    Temp Access Pass - State
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAT01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Temp Access Pass - State' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $TAPConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'TemporaryAccessPass' }

        if (-not $TAPConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAT01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'Temporary Access Pass configuration not found in Authentication Methods Policy.' -Risk 'Medium' -Name 'Temp Access Pass - State' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        if ($TAPConfig.state -eq 'enabled') {
            $Status = 'Passed'
            $Result = 'Temporary Access Pass is enabled'
        } else {
            $Status = 'Failed'
            $Result = @"
Temporary Access Pass should be enabled to facilitate secure onboarding of passwordless authentication methods.

**Current Configuration:**
- State: $($TAPConfig.state)

**Recommended Configuration:**
- State: enabled

Enabling TAP allows administrators to securely onboard users to passwordless authentication.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAT01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Temp Access Pass - State' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAT01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Temp Access Pass - State' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
