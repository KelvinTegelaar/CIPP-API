function Invoke-CippTestCIS_5_2_2_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.3) - Conditional Access policies SHALL block legacy authentication
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Conditional Access policies block legacy authentication' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $LegacyClients = @('exchangeActiveSync', 'other')
        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.grantControls.builtInControls -contains 'block' -and
            $_.conditions.clientAppTypes -and
            ($_.conditions.clientAppTypes | Where-Object { $_ -in $LegacyClients }).Count -gt 0
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies block legacy authentication:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets legacy authentication client app types with a Block grant.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Conditional Access policies block legacy authentication' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Conditional Access policies block legacy authentication' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
