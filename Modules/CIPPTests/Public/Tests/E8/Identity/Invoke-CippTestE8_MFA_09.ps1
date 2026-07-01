function Invoke-CippTestE8_MFA_09 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML3) - Number matching is enforced for Microsoft Authenticator
    #>
    param($Tenant)

    $TestId = 'E8_MFA_09'
    $Name = 'Microsoft Authenticator number matching is enforced'

    try {
        $AuthMethodsPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'
        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - MFA'
            return
        }

        $MsAuth = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' }
        if (-not $MsAuth -or $MsAuth.state -ne 'enabled') {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'Microsoft Authenticator method is not enabled in the tenant.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - MFA'
            return
        }

        $NumberMatching = $MsAuth.featureSettings.numberMatchingRequiredState
        $Issues = [System.Collections.Generic.List[string]]::new()
        if ($NumberMatching.state -ne 'enabled') {
            $Issues.Add("numberMatchingRequiredState.state is '$($NumberMatching.state)' (expected 'enabled').")
        }
        if ($NumberMatching.includeTarget.id -and $NumberMatching.includeTarget.id -ne 'all_users') {
            $Issues.Add("numberMatchingRequiredState.includeTarget is '$($NumberMatching.includeTarget.id)' (expected 'all_users').")
        }

        if ($Issues.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'Microsoft Authenticator number matching is enabled and targets all users.'
        } else {
            $Status = 'Failed'
            $Result = "Microsoft Authenticator number matching is not fully enforced:`n`n$(($Issues | ForEach-Object { "- $_" }) -join "`n")"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML3 - MFA'
    }
}
