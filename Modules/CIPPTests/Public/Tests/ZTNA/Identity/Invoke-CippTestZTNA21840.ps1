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
        $AuthMethodsPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

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

        $ResultMarkdown = [System.Text.StringBuilder]::new("`n## [Security key attestation policy details]($PortalLink)`n")

        $AttestationStatus = if ($IsAttestationEnforced -eq $true) { 'True ✅' } else { 'False ❌' }
        $null = $ResultMarkdown.Append("- **Enforce attestation** : $AttestationStatus`n")

        if ($KeyRestrictions) {
            $null = $ResultMarkdown.Append("- **Key restriction policy** :`n")
            if ($null -ne $KeyRestrictions.isEnforced) {
                $null = $ResultMarkdown.Append("  - **Enforce key restrictions** : $($KeyRestrictions.isEnforced)`n")
            } else {
                $null = $ResultMarkdown.Append("  - **Enforce key restrictions** : Not configured`n")
            }
            if ($KeyRestrictions.enforcementType) {
                $null = $ResultMarkdown.Append("  - **Restrict specific keys** : $($KeyRestrictions.enforcementType)`n")
            } else {
                $null = $ResultMarkdown.Append("  - **Restrict specific keys** : Not configured`n")
            }

            if ($KeyRestrictions.aaGuids -and $KeyRestrictions.aaGuids.Count -gt 0) {
                $null = $ResultMarkdown.Append("  - **AAGUID** :`n")
                foreach ($Guid in $KeyRestrictions.aaGuids) {
                    $null = $ResultMarkdown.Append("    - $Guid`n")
                }
            }
        }

        $Passed = if ($IsAttestationEnforced -eq $true) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = [System.Text.StringBuilder]::new("Security key attestation is properly enforced, ensuring only verified hardware authenticators can be registered.$ResultMarkdown")
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new("Security key attestation is not enforced, allowing unverified or potentially compromised security keys to be registered.$ResultMarkdown")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Security key attestation is enforced' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Security key attestation is enforced' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
