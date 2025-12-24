function Invoke-CippTestZTNA21886 {
    param($Tenant)

    try {
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'
        if (-not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21886' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Service principal data not found in database' -Risk 'Medium' -Name 'Applications are configured for automatic user provisioning' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Applications management'
            return
        }

        $AppsWithSSO = $ServicePrincipals | Where-Object {
            $null -ne $_.preferredSingleSignOnMode -and
            $_.preferredSingleSignOnMode -in @('password', 'saml', 'oidc') -and
            $_.accountEnabled -eq $true
        }

        if (-not $AppsWithSSO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21886' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No applications configured for SSO found' -Risk 'Medium' -Name 'Applications are configured for automatic user provisioning' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Applications management'
            return
        }

        $Status = 'Investigate'
        $Result = "Found $($AppsWithSSO.Count) application(s) configured for SSO. Provisioning template and job validation requires Graph API synchronization endpoint not available in cache."

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21886' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Applications are configured for automatic user provisioning' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Applications management'
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21886' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Applications are configured for automatic user provisioning' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Applications management'
    }
}
