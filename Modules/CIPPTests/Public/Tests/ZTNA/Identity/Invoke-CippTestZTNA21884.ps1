function Invoke-CippTestZTNA21884 {
    <#
    .SYNOPSIS
    Workload identities based on known networks are configured
    #>
    param($Tenant)

    try {
        $CAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21884' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Workload identities based on known networks are configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
            return
        }

        # A workload-identity CA policy targets service principals AND uses a location condition.
        $WorkloadPolicies = [System.Collections.Generic.List[object]]::new()
        foreach ($P in $CAPolicies) {
            if ($P.state -ne 'enabled') { continue }
            $TargetsWorkload = ($P.conditions.clientApplications.includeServicePrincipals.Count -gt 0) -or
            ($P.conditions.clientApplications.includeServicePrincipals -contains 'All') -or
            ($P.conditions.clientApplications.includeServicePrincipals -contains 'ServicePrincipalsInMyTenant')

            $HasLocation = ($P.conditions.locations.includeLocations.Count -gt 0) -or
            ($P.conditions.locations.excludeLocations.Count -gt 0)

            if ($TargetsWorkload -and $HasLocation) {
                $WorkloadPolicies.Add($P)
            }
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($WorkloadPolicies.Count -gt 0) {
            $Status = 'Passed'
            $Lines.Add("Found $($WorkloadPolicies.Count) enabled Conditional Access policy(s) protecting workload identities with location conditions.")
            $Lines.Add('')
            $Lines.Add('| Policy Name | State |')
            $Lines.Add('| :---------- | :---- |')
            foreach ($P in ($WorkloadPolicies | Select-Object -First 25)) {
                $Lines.Add("| $($P.displayName) | $($P.state) |")
            }
        } else {
            $Status = 'Failed'
            $Lines.Add('No enabled Conditional Access policies were found that target workload identities (service principals) and include a location condition.')
            $Lines.Add('')
            $Lines.Add('**Remediation:** Create a Conditional Access policy targeting service principals (`clientApplications.includeServicePrincipals`) with a trusted named-location condition. Requires Microsoft Entra Workload Identities license.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21884' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'High' -Name 'Workload identities based on known networks are configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21884' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Workload identities based on known networks are configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
    }
}
