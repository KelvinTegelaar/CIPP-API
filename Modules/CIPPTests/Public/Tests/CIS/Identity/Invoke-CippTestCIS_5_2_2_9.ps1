function Invoke-CippTestCIS_5_2_2_9 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.9) - A managed device SHALL be required for authentication
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_9' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'A managed device is required for authentication' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Device Management'
            return
        }

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.grantControls -and (
                $_.grantControls.builtInControls -contains 'compliantDevice' -or
                $_.grantControls.builtInControls -contains 'domainJoinedDevice'
            )
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies require a compliant or domain-joined device:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy requires a compliant or hybrid-joined device.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_9' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'A managed device is required for authentication' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Device Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_9' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'A managed device is required for authentication' -UserImpact 'High' -ImplementationEffort 'High' -Category 'Device Management'
    }
}
