function Invoke-CippTestZTNA21874 {
    param($Tenant)

    $TestId = 'ZTNA21874'
    #Trusted
    try {
        # Get B2B Management Policy from cache
        $B2BManagementPolicyObject = New-CIPPDbRequest -TenantFilter $Tenant -Type 'B2BManagementPolicy'

        if (-not $B2BManagementPolicyObject) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'B2B Management Policy not found in cache' -Risk 'Medium' -Name 'Guest access is limited to approved tenants' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'External collaboration'
            return
        }

        $Passed = 'Failed'
        $AllowedDomains = $null

        if ($B2BManagementPolicyObject.definition) {
            $B2BManagementPolicy = ($B2BManagementPolicyObject.definition | ConvertFrom-Json).B2BManagementPolicy
            $AllowedDomains = $B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy.AllowedDomains

            if ($AllowedDomains -and $AllowedDomains.Count -gt 0) {
                $Passed = 'Passed'
            }
        }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = '✅ Allow/Deny lists of domains to restrict external collaboration are configured.'
        } else {
            $ResultMarkdown = '❌ Allow/Deny lists of domains to restrict external collaboration are not configured.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Guest access is limited to approved tenants' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External collaboration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guest access is limited to approved tenants' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'External collaboration'
    }
}
