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
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

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

        $ResultMarkdown = "`n## [Passkey authentication method details]($PortalLink)`n"

        $StatusDisplay = if ($Fido2Enabled) { 'Enabled ✅' } else { 'Disabled ❌' }
        $ResultMarkdown += "- **Status** : $StatusDisplay`n"

        if ($Fido2Enabled) {
            $ResultMarkdown += '- **Include targets** : '
            if ($IncludeTargets) {
                $TargetsDisplay = ($IncludeTargets | ForEach-Object {
                        if ($_.id -eq 'all_users') { 'All users' } else { $_.id }
                    }) -join ', '
                $ResultMarkdown += "$TargetsDisplay`n"
            } else {
                $ResultMarkdown += "None`n"
            }

            $ResultMarkdown += "- **Enforce attestation** : $IsAttestationEnforced`n"

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
            }
        }

        $Passed = if ($Fido2Enabled -and $HasIncludeTargets) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = "Passkey authentication method is enabled and configured for users in your tenant.$ResultMarkdown"
        } else {
            $ResultMarkdown = "Passkey authentication method is not enabled or not configured for any users in your tenant.$ResultMarkdown"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Passkey authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Passkey authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential management'
    }
}
