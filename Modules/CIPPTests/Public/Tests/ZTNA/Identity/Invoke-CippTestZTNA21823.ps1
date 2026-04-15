function Invoke-CippTestZTNA21823 {
    <#
    .SYNOPSIS
    Guest self-service sign-up via user flow is disabled
    #>
    param($Tenant)

    $TestId = 'ZTNA21823'
    #Tested
    try {
        # Get authentication flows policy from cache
        $AuthFlowPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationFlowsPolicy'

        if (-not $AuthFlowPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Guest self-service sign-up via user flow is disabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External collaboration'
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
