function Invoke-CippTestZTNA21823 {
    param($Tenant)

    $TestId = 'ZTNA21823'

    try {
        # Get authentication flows policy
        $AuthFlowPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/authenticationFlowsPolicy' -tenantid $Tenant

        if (-not $AuthFlowPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Authentication flows policy not found' -Risk 'Medium' -Name 'Guest self-service sign-up via user flow is disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External collaboration'
            return
        }

        $Passed = if ($AuthFlowPolicy.selfServiceSignUp.isEnabled -eq $false) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = "[Guest self-service sign up via user flow](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/CompanyRelationshipsMenuBlade/~/Settings/menuId/ExternalIdentitiesGettingStarted) is disabled.`n"
        } else {
            $ResultMarkdown = "[Guest self-service sign up via user flow](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/CompanyRelationshipsMenuBlade/~/Settings/menuId/ExternalIdentitiesGettingStarted) is enabled.`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Guest self-service sign-up via user flow is disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External collaboration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guest self-service sign-up via user flow is disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External collaboration'
    }
}
