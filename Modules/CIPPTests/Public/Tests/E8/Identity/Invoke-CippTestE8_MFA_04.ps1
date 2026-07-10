function Invoke-CippTestE8_MFA_04 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML2) - At least one phishing-resistant authentication method is enabled
    #>
    param($Tenant)

    $TestId = 'E8_MFA_04'
    $Name = 'A phishing-resistant authentication method is enabled in the tenant'

    try {
        $AuthMethodsPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'
        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML2 - MFA'
            return
        }

        # Windows Hello for Business is provisioned via Intune / device registration and is not part of
        # authenticationMethodConfigurations, so it cannot be evaluated from this policy.
        $Configs = $AuthMethodsPolicy.authenticationMethodConfigurations
        $Enabled = [System.Collections.Generic.List[string]]::new()
        foreach ($Id in 'Fido2','X509Certificate') {
            $C = $Configs | Where-Object { $_.id -eq $Id }
            if ($C -and $C.state -eq 'enabled') { $Enabled.Add($Id) }
        }

        if ($Enabled.Count -gt 0) {
            $Status = 'Passed'
            $Result = "Phishing-resistant authentication method(s) enabled: $($Enabled -join ', ')."
        } else {
            $Status = 'Failed'
            $Result = 'No phishing-resistant authentication method (FIDO2 security key or X509 certificate-based auth) is enabled in the tenant. Windows Hello for Business is managed via Intune and is not evaluated by this test.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML2 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'E8 ML2 - MFA'
    }
}
