function Invoke-CippTestCIS_5_2_2_10 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.10) - A managed device SHALL be required to register security information
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_10' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'A managed device is required to register security information' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Authentication'
            return
        }

        # User Action GUID for "Register security information"
        $RegSecInfo = 'cb1d5f30-e5dc-4d70-b3f1-5ab8e3c9d3c0'

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.applications.includeUserActions -contains 'urn:user:registersecurityinfo' -and
            ($_.grantControls.builtInControls -contains 'compliantDevice' -or
             $_.grantControls.builtInControls -contains 'domainJoinedDevice' -or
             ($_.conditions.locations -and $_.conditions.locations.includeLocations))
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies guard the Register security info user action:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets the Register security info user action with a managed-device or trusted-location requirement.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_10' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'A managed device is required to register security information' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_10' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'A managed device is required to register security information' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Authentication'
    }
}
