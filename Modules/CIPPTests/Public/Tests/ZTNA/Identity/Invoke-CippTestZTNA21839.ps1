function Invoke-CippTestZTNA21839 {
    <#
    .SYNOPSIS
    Passkey authentication method enabled
    #>
    param($Tenant)

    $TestId = 'ZTNA21839'
    #Tested
    try {
        # Get FIDO2 authentication method policy
        $AuthMethodsPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Passkey authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential management'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Passkey authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential management'
            return
        }

        $State = $Fido2Config.state
        $IncludeTargets = $Fido2Config.includeTargets
        $IsAttestationEnforced = $Fido2Config.isAttestationEnforced
        $KeyRestrictions = $Fido2Config.keyRestrictions

        $Fido2Enabled = $State -eq 'enabled'
        $HasIncludeTargets = $IncludeTargets -and $IncludeTargets.Count -gt 0

        $PortalLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods'

        $ResultMarkdown = [System.Text.StringBuilder]::new("`n## [Passkey authentication method details]($PortalLink)`n")

        $StatusDisplay = if ($Fido2Enabled) { 'Enabled ✅' } else { 'Disabled ❌' }
        $null = $ResultMarkdown.Append("- **Status** : $StatusDisplay`n")

        if ($Fido2Enabled) {
            $null = $ResultMarkdown.Append('- **Include targets** : ')
            if ($IncludeTargets) {
                $TargetsDisplay = ($IncludeTargets | ForEach-Object {
                        if ($_.id -eq 'all_users') { 'All users' } else { $_.id }
                    }) -join ', '
                $null = $ResultMarkdown.Append("$TargetsDisplay`n")
            } else {
                $null = $ResultMarkdown.Append("None`n")
            }

            $null = $ResultMarkdown.Append("- **Enforce attestation** : $IsAttestationEnforced`n")

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
            }
        }

        $Passed = if ($Fido2Enabled -and $HasIncludeTargets) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = [System.Text.StringBuilder]::new("Passkey authentication method is enabled and configured for users in your tenant.$ResultMarkdown")
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new("Passkey authentication method is not enabled or not configured for any users in your tenant.$ResultMarkdown")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Passkey authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Passkey authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential management'
    }
}
