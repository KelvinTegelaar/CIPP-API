function Invoke-CippTestEIDSCAAF02 {
    <#
    .SYNOPSIS
    FIDO2 - Self-Service
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF02' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'FIDO2 - Self-Service' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF02' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'FIDO2 configuration not found in Authentication Methods Policy.' -Risk 'Low' -Name 'FIDO2 - Self-Service' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        if ($Fido2Config.isSelfServiceRegistrationAllowed -eq $true) {
            $Status = 'Passed'
            $Result = 'FIDO2 self-service registration is enabled'
        } else {
            $Status = 'Failed'
            $Result = @"
FIDO2 self-service registration should be enabled to allow users to register their own security keys.

**Current Configuration:**
- isSelfServiceRegistrationAllowed: $($Fido2Config.isSelfServiceRegistrationAllowed)

**Recommended Configuration:**
- isSelfServiceRegistrationAllowed: true

Enabling self-service registration improves user experience and adoption of FIDO2 security keys.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF02' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'FIDO2 - Self-Service' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF02' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'FIDO2 - Self-Service' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
