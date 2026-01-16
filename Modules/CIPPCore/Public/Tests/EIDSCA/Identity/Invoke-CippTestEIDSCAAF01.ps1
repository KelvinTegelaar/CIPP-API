function Invoke-CippTestEIDSCAAF01 {
    <#
    .SYNOPSIS
    FIDO2 - State
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'FIDO2 - State' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'FIDO2 configuration not found in Authentication Methods Policy.' -Risk 'Low' -Name 'FIDO2 - State' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        if ($Fido2Config.state -eq 'enabled') {
            $Status = 'Passed'
            $Result = 'FIDO2 authentication method is enabled'
        } else {
            $Status = 'Failed'
            $Result = @"
FIDO2 security keys should be enabled to provide strong, phishing-resistant authentication.

**Current Configuration:**
- State: $($Fido2Config.state)

**Recommended Configuration:**
- State: enabled

Enabling FIDO2 provides users with a secure, passwordless authentication option.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'FIDO2 - State' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'FIDO2 - State' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    }
}
