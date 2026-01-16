function Invoke-CippTestZTNA21840 {
    <#
    .SYNOPSIS
    Security key attestation is enforced
    #>
    param($Tenant)
    #Tested
    $TestId = 'ZTNA21840'

    try {
        # Get FIDO2 authentication method policy
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Security key attestation is enforced' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Security key attestation is enforced' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        $IsAttestationEnforced = $Fido2Config.isAttestationEnforced
        $KeyRestrictions = $Fido2Config.keyRestrictions

        $PortalLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods'

        $ResultMarkdown = "`n## [Security key attestation policy details]($PortalLink)`n"

        $AttestationStatus = if ($IsAttestationEnforced -eq $true) { 'True ✅' } else { 'False ❌' }
        $ResultMarkdown += "- **Enforce attestation** : $AttestationStatus`n"

        if ($KeyRestrictions) {
            $ResultMarkdown += "- **Key restriction policy** :`n"
            if ($null -ne $KeyRestrictions.isEnforced) {
                $ResultMarkdown += "  - **Enforce key restrictions** : $($KeyRestrictions.isEnforced)`n"
            } else {
                $ResultMarkdown += "  - **Enforce key restrictions** : Not configured`n"
            }
            if ($KeyRestrictions.enforcementType) {
                $ResultMarkdown += "  - **Restrict specific keys** : $($KeyRestrictions.enforcementType)`n"
            } else {
                $ResultMarkdown += "  - **Restrict specific keys** : Not configured`n"
            }

            if ($KeyRestrictions.aaGuids -and $KeyRestrictions.aaGuids.Count -gt 0) {
                $ResultMarkdown += "  - **AAGUID** :`n"
                foreach ($Guid in $KeyRestrictions.aaGuids) {
                    $ResultMarkdown += "    - $Guid`n"
                }
            }
        }

        $Passed = if ($IsAttestationEnforced -eq $true) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = "Security key attestation is properly enforced, ensuring only verified hardware authenticators can be registered.$ResultMarkdown"
        } else {
            $ResultMarkdown = "Security key attestation is not enforced, allowing unverified or potentially compromised security keys to be registered.$ResultMarkdown"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Security key attestation is enforced' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Security key attestation is enforced' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
