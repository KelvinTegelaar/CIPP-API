function Invoke-CippTestCIS_5_2_2_15 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.2.15) - Exclusionary geographic access controls are utilized
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_15' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'Exclusionary geographic access controls are utilized' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication'
            return
        }

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeUsers -contains 'All' -and
            $_.conditions.applications.includeApplications -contains 'All' -and
            $_.grantControls.builtInControls -contains 'block' -and
            $_.conditions.locations -and
            # Include at least one untrusted/selected location (a GUID, not just 'AllTrusted')
            ($_.conditions.locations.includeLocations | Where-Object { $_ -and $_ -ne 'AllTrusted' }) -and
            # Exclude trusted locations: AllTrusted, or at least one location GUID
            (
                $_.conditions.locations.excludeLocations -contains 'AllTrusted' -or
                ($_.conditions.locations.excludeLocations | Where-Object { $_ })
            )
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) enabled Conditional Access policy/policies block access from untrusted locations while excluding trusted locations:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled block policy was found that includes untrusted locations for all users/apps and excludes trusted locations.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_15' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Exclusionary geographic access controls are utilized' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_15' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Exclusionary geographic access controls are utilized' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication'
    }
}
