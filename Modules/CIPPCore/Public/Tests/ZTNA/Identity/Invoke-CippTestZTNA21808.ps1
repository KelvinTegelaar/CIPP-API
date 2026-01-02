function Invoke-CippTestZTNA21808 {
    <#
    .SYNOPSIS
    Restrict device code flow
    #>
    param($Tenant)
    #Tested
    try {
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21808' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Restrict device code flow' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        $Enabled = $CAPolicies | Where-Object { $_.state -eq 'enabled' }
        $DeviceCodePolicies = $Enabled | Where-Object {
            if ($_.conditions.authenticationFlows.transferMethods) {
                $Methods = $_.conditions.authenticationFlows.transferMethods -split ','
                $Methods -contains 'deviceCodeFlow'
            } else {
                $false
            }
        }

        $BlockPolicies = $DeviceCodePolicies | Where-Object { $_.grantControls.builtInControls -contains 'block' }

        if ($BlockPolicies.Count -gt 0) {
            $Status = 'Passed'
            $Result = "Device code flow is properly restricted with $($BlockPolicies.Count) blocking policy/policies"
        } elseif ($DeviceCodePolicies.Count -eq 0) {
            $Status = 'Failed'
            $Result = 'No Conditional Access policies found targeting device code flow'
            #Add table with existing policies?
        } else {
            $Status = 'Failed'
            $Result = 'Device code flow policies exist but none are configured to block'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21808' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Restrict device code flow' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21808' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Restrict device code flow' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access Control'
    }
}
