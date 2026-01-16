function Invoke-CippTestEIDSCAAF03 {
    <#
    .SYNOPSIS
    FIDO2 - Attestation
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF03' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'FIDO2 - Attestation' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF03' -TestType 'Identity' -Status 'Failed' -ResultMarkdown 'FIDO2 configuration not found in Authentication Methods Policy.' -Risk 'Medium' -Name 'FIDO2 - Attestation' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
            return
        }

        if ($Fido2Config.isAttestationEnforced -eq $true) {
            $Status = 'Passed'
            $Result = 'FIDO2 attestation enforcement is enabled'
        } else {
            $Status = 'Failed'
            $Result = @"
FIDO2 attestation should be enforced to verify the authenticity and security of FIDO2 security keys.

**Current Configuration:**
- isAttestationEnforced: $($Fido2Config.isAttestationEnforced)

**Recommended Configuration:**
- isAttestationEnforced: true

Enforcing attestation ensures that only trusted and verified security keys can be registered.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF03' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'FIDO2 - Attestation' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAF03' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'FIDO2 - Attestation' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication Methods'
    }
}
