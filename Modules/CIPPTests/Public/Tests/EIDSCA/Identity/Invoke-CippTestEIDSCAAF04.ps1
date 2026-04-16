function Invoke-CippTestEIDSCAAF04 {
    <#
    .SYNOPSIS
    FIDO2 - Key Restrictions
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF04' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'FIDO2 - Key Restrictions' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF04' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'FIDO2 configuration not found in Authentication Methods Policy.' -Risk 'Medium' -Name 'FIDO2 - Key Restrictions' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        if ($Fido2Config.keyRestrictions.isEnforced -eq $true) {
            $Status = 'Passed'
            $Result = 'FIDO2 key restrictions are enforced'
        } else {
            $Status = 'Failed'
            $Result = @"
FIDO2 key restrictions should be enforced to control which security keys can be registered.

**Current Configuration:**
- keyRestrictions.isEnforced: $($Fido2Config.keyRestrictions.isEnforced)

**Recommended Configuration:**
- keyRestrictions.isEnforced: true

Enforcing key restrictions helps ensure only approved security keys are used in your organization.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF04' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'FIDO2 - Key Restrictions' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF04' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'FIDO2 - Key Restrictions' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    }
}
