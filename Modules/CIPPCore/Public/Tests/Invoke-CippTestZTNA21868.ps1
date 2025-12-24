function Invoke-CippTestZTNA21868 {
    param($Tenant)

    try {
        $Guests = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Guests'
        $Apps = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Apps'
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'

        if (-not $Guests -or -not $Apps -or -not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21868' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Required data not found in database' -Risk 'Medium' -Name 'Guests do not own apps in the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
            return
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21868' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'This test requires Graph API calls to check application and service principal ownership. Owner relationships are not cached.' -Risk 'Medium' -Name 'Guests do not own apps in the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21868' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guests do not own apps in the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
    }
}
