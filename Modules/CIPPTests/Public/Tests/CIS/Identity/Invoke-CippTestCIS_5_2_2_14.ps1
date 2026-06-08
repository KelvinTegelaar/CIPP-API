function Invoke-CippTestCIS_5_2_2_14 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.2.14) - Named locations are defined and applied
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_14' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'Named locations are defined and applied' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        # A named location reference is any include/exclude location GUID (i.e. not 'All' or 'AllTrusted')
        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.locations -and
            (
                ($_.conditions.locations.includeLocations | Where-Object { $_ -and $_ -notin @('All', 'AllTrusted') }) -or
                ($_.conditions.locations.excludeLocations | Where-Object { $_ -and $_ -notin @('All', 'AllTrusted') })
            )
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) enabled Conditional Access policy/policies reference a named location:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy references a defined named location in its location conditions.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_14' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Named locations are defined and applied' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_14' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Named locations are defined and applied' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
