function Invoke-CippTestE8_MFA_03 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML1) - Legacy authentication is blocked
    #>
    param($Tenant)

    $TestId = 'E8_MFA_03'
    $Name = 'Legacy authentication is blocked tenant-wide'

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
            return
        }

        $Match = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            ($_.conditions.users.includeUsers -contains 'All') -and
            ($_.conditions.clientAppTypes -contains 'exchangeActiveSync' -or $_.conditions.clientAppTypes -contains 'other') -and
            ($_.grantControls.builtInControls -contains 'block')
        }

        if ($Match) {
            $Status = 'Passed'
            $Result = "$($Match.Count) Conditional Access policy/policies block legacy auth:`n`n" +
                (($Match | ForEach-Object { "- $($_.displayName)" }) -join "`n")
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy blocks legacy authentication clients (`exchangeActiveSync`/`other`). MFA can be bypassed via legacy protocols if not blocked.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
    }
}
