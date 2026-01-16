function Invoke-CippTestZTNA21796 {
    <#
    .SYNOPSIS
    Block legacy authentication policy is configured
    #>
    param($Tenant)
    #tested
    try {
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21796' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Block legacy authentication policy is configured' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        $BlockPolicies = $CAPolicies | Where-Object {
            $_.grantControls.builtInControls -contains 'block' -and
            $_.conditions.clientAppTypes -contains 'exchangeActiveSync' -and
            $_.conditions.clientAppTypes -contains 'other'
        }

        $EnabledBlockPolicies = $BlockPolicies | Where-Object {
            $_.conditions.users.includeUsers -contains 'All' -and
            $_.state -eq 'enabled'
        }

        if ($EnabledBlockPolicies.Count -ge 1) {
            $Status = 'Passed'
            $Result = "Found $($EnabledBlockPolicies.Count) properly configured policies blocking legacy authentication:`n $($EnabledBlockPolicies | ForEach-Object { "- $($_.displayName)" } | Out-String) "
        } elseif ($BlockPolicies.Count -ge 1) {
            $Status = 'Failed'
            $Result = "Policies to block legacy authentication found but not properly configured or enabled: `n $($BlockPolicies | ForEach-Object { "- $($_.displayName)" } | Out-String) "
        } else {
            $Status = 'Failed'
            $Result = 'No conditional access policies to block legacy authentication found'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21796' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Block legacy authentication policy is configured' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Access Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21796' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Block legacy authentication policy is configured' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Access Control'
    }
}
