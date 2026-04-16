function Invoke-CippTestZTNA21830 {
    <#
    .SYNOPSIS
    Conditional Access policies for Privileged Access Workstations are configured
    #>
    param($Tenant)

    $TestId = 'ZTNA21830'
    #Tested
    try {
        # Get Conditional Access policies
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $EnabledCAPolicies = $CAPolicies | Where-Object { $_.state -eq 'enabled' }

        # Get privileged roles
        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles

        if (-not $PrivilegedRoles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Conditional Access policies for Privileged Access Workstations are configured' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
            return
        }

        $CompliantDevicePolicies = [System.Collections.Generic.List[object]]::new()
        $DeviceFilterPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $EnabledCAPolicies) {
            # Check if policy targets privileged roles
            $TargetsPrivilegedRoles = $false
            if ($Policy.conditions.users.includeRoles) {
                foreach ($RoleId in $Policy.conditions.users.includeRoles) {
                    if ($PrivilegedRoles.id -contains $RoleId) {
                        $TargetsPrivilegedRoles = $true
                        break
                    }
                }
            }

            if ($TargetsPrivilegedRoles) {
                # Check for compliant device control
                if ($Policy.grantControls.builtInControls -contains 'compliantDevice') {
                    $CompliantDevicePolicies.Add($Policy)
                }

                # Check for device filter exclude + block
                $HasDeviceFilterExclude = $Policy.conditions.devices.deviceFilter -and
                $Policy.conditions.devices.deviceFilter.mode -eq 'exclude'
                $BlocksAccess = (-not $Policy.grantControls.builtInControls) -or
                ($Policy.grantControls.builtInControls -contains 'block')

                if ($HasDeviceFilterExclude -and $BlocksAccess) {
                    $DeviceFilterPolicies.Add($Policy)
                }
            }
        }

        $Passed = if ($CompliantDevicePolicies.Count -eq 0 -or $DeviceFilterPolicies.Count -eq 0) { 'Failed' } else { 'Passed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = 'Conditional Access policies restrict privileged role access to PAW devices.'
        } else {
            $ResultMarkdown = 'No Conditional Access policies found that restrict privileged roles to PAW device.'
        }

        $CompliantDeviceMarkdown = if ($CompliantDevicePolicies.Count -gt 0) { '✅' } else { '❌' }
        $DeviceFilterMarkdown = if ($DeviceFilterPolicies.Count -gt 0) { '✅' } else { '❌' }

        $ResultMarkdown += "`n`n**$CompliantDeviceMarkdown Found $($CompliantDevicePolicies.Count) policy(s) with compliant device control targeting all privileged roles**`n"
        foreach ($Policy in $CompliantDevicePolicies) {
            $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)"
            $ResultMarkdown += "- **Policy:** [$($Policy.displayName)]($PortalLink)`n"
        }

        $ResultMarkdown += "`n`n**$DeviceFilterMarkdown Found $($DeviceFilterPolicies.Count) policy(s) with PAW/SAW device filter targeting all privileged roles**`n"
        foreach ($Policy in $DeviceFilterPolicies) {
            $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)"
            $ResultMarkdown += "- **Policy:** [$($Policy.displayName)]($PortalLink)`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Conditional Access policies for Privileged Access Workstations are configured' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Conditional Access policies for Privileged Access Workstations are configured' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
    }
}
