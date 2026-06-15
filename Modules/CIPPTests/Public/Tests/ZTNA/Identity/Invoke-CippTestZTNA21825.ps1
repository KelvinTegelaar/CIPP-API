function Invoke-CippTestZTNA21825 {
    <#
    .SYNOPSIS
    Privileged users have short-lived sign-in sessions
    #>
    param($Tenant)

    $TestId = 'ZTNA21825'
    #Tested
    try {
        # Get privileged roles
        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles

        if (-not $PrivilegedRoles -or $PrivilegedRoles.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Privileged users have short-lived sign-in sessions' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access control'
            return
        }

        # Get Conditional Access policies
        $CAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        # Filter to policies targeting roles
        $RoleScopedPolicies = $CAPolicies | Where-Object {
            $_.conditions.users.includeRoles -and $_.conditions.users.includeRoles.Count -gt 0
        }

        # Recommended: Sign-in frequency should be 4 hours or less for privileged users
        $RecommendedMaxHours = 4

        $ResultMarkdown = [System.Text.StringBuilder]::new("## Privileged User Sign-In Sessions`n`n")
        $null = $ResultMarkdown.Append("**Total Privileged Roles Found:** $($PrivilegedRoles.Count)`n`n")
        $null = $ResultMarkdown.Append("**CA Policies Targeting Roles:** $($RoleScopedPolicies.Count)`n`n")
        $null = $ResultMarkdown.Append("**Recommended Sign In Session Hours:** $RecommendedMaxHours`n`n")
        $null = $ResultMarkdown.Append("### Conditional Access Policies by Privileged Role`n`n")

        $AllRolesCovered = $true

        foreach ($Role in $PrivilegedRoles) {
            $null = $ResultMarkdown.Append("#### $($Role.displayName)`n`n")

            # Get CA policies assigned to this role
            $AssignedPolicies = $CAPolicies | Where-Object { $_.conditions.users.includeRoles -contains $Role.id }
            $EnabledPolicies = $AssignedPolicies | Where-Object { $_.state -eq 'enabled' }

            if ($EnabledPolicies.Count -gt 0) {
                # Check if at least one compliant enabled policy covers this role
                $CompliantForRole = $EnabledPolicies | Where-Object {
                    $_.sessionControls.signInFrequency -and
                    $_.sessionControls.signInFrequency.type -eq 'hours' -and
                    $_.sessionControls.signInFrequency.value -le $RecommendedMaxHours
                }

                $RoleStatus = if ($CompliantForRole.Count -gt 0) {
                    '✅ Covered'
                } else {
                    '❌ Not Covered'; $AllRolesCovered = $false
                }
                $null = $ResultMarkdown.Append("**Status:** $RoleStatus`n`n")

                $null = $ResultMarkdown.Append("| Policy Name | Sign-In Frequency | Compliant |`n")
                $null = $ResultMarkdown.Append("| :--- | :--- | :--- |`n")

                foreach ($Policy in $EnabledPolicies) {
                    $FreqValue = 'Not Configured'
                    $IsCompliant = '❌'

                    if ($Policy.sessionControls.signInFrequency) {
                        $Freq = $Policy.sessionControls.signInFrequency
                        $FreqValue = "$($Freq.value) $($Freq.type)"

                        if ($Freq.type -eq 'hours' -and $Freq.value -le $RecommendedMaxHours) {
                            $IsCompliant = '✅'
                        } elseif ($Freq.type -eq 'hours') {
                            $IsCompliant = "⚠️ ($($Freq.value)h > $($RecommendedMaxHours)h)"
                        } else {
                            $IsCompliant = '❌ (Days not recommended)'
                        }
                    }

                    $PolicyLink = "https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)"
                    $null = $ResultMarkdown.Append("| [$($Policy.displayName)]($PolicyLink) | $FreqValue | $IsCompliant |`n")
                }
                $null = $ResultMarkdown.Append("`n")
            } else {
                $null = $ResultMarkdown.Append("**Status:** ❌ No CA policies assigned`n`n")
                $null = $ResultMarkdown.Append("*No Conditional Access policies target this privileged role.*`n`n")
                $AllRolesCovered = $false
            }
        }

        $Passed = if ($AllRolesCovered -and $PrivilegedRoles.Count -gt 0) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $null = $ResultMarkdown.Append("✅ **All privileged roles are covered by enabled policies enforcing short-lived sessions (≤$RecommendedMaxHours hours).**`n")
        } else {
            $null = $ResultMarkdown.Append("❌ **Not all privileged roles are covered by compliant sign-in frequency controls.**`n")
            $null = $ResultMarkdown.Append("`n**Recommendation:** Configure Conditional Access policies to enforce sign-in frequency of $RecommendedMaxHours hours or less for ALL privileged roles.`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Privileged users have short-lived sign-in sessions' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Privileged users have short-lived sign-in sessions' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access control'
    }
}
