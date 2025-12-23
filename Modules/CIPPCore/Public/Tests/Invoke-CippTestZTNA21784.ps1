function Invoke-CippTestZTNA21784 {
    param($Tenant)

    try {
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21784' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Conditional Access policies not found in database' -Risk 'Medium' -Name 'All user sign in activity uses phishing-resistant authentication methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        $EnabledPolicies = $CAPolicies | Where-Object { $_.state -eq 'enabled' }

        $AllUsersPolicies = $EnabledPolicies | Where-Object {
            $_.conditions.users.includeUsers -contains 'All' -and
            $_.grantControls.authenticationStrength
        }

        if (-not $AllUsersPolicies) {
            $Status = 'Failed'
            $Result = 'No Conditional Access policies found requiring phishing-resistant authentication for all users'
        } else {
            $PoliciesWithExclusions = $AllUsersPolicies | Where-Object {
                $_.conditions.users.excludeUsers.Count -gt 0
            }

            if ($PoliciesWithExclusions.Count -gt 0) {
                $Status = 'Failed'
                $Result = "Found $($AllUsersPolicies.Count) policies requiring phishing-resistant authentication, but $($PoliciesWithExclusions.Count) have user exclusions creating coverage gaps"
            } else {
                $Status = 'Passed'
                $Result = "All users are protected by $($AllUsersPolicies.Count) Conditional Access policies requiring phishing-resistant authentication"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21784' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'All user sign in activity uses phishing-resistant authentication methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21784' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'All user sign in activity uses phishing-resistant authentication methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    }
}
