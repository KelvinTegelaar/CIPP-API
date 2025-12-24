function Invoke-CippTestZTNA21869 {
    param($Tenant)

    try {
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'
        if (-not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21869' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Service principal data not found in database' -Risk 'Medium' -Name 'Enterprise applications must require explicit assignment or scoped provisioning' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $AppsWithoutAssignment = $ServicePrincipals | Where-Object {
            $_.appRoleAssignmentRequired -eq $false -and
            $null -ne $_.preferredSingleSignOnMode -and
            $_.preferredSingleSignOnMode -in @('password', 'saml', 'oidc') -and
            $_.accountEnabled -eq $true
        }

        if (-not $AppsWithoutAssignment) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21869' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'All enterprise applications have explicit assignment requirements' -Risk 'Medium' -Name 'Enterprise applications must require explicit assignment or scoped provisioning' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $Status = 'Investigate'
        $Result = "Found $($AppsWithoutAssignment.Count) enterprise application(s) without assignment requirements. Full provisioning scope validation requires Graph API calls not available in cache."

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21869' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Enterprise applications must require explicit assignment or scoped provisioning' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21869' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Enterprise applications must require explicit assignment or scoped provisioning' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
    }
}
