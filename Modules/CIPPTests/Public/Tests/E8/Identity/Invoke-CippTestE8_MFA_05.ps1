function Invoke-CippTestE8_MFA_05 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML2) - Weak authentication methods (SMS / Voice / Email OTP) are disabled
    #>
    param($Tenant)

    $TestId = 'E8_MFA_05'
    $Name = 'Weak MFA methods (SMS, Voice call, Email OTP) are disabled'

    try {
        $AuthMethodsPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'
        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found.' -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML2 - MFA'
            return
        }

        $Configs = $AuthMethodsPolicy.authenticationMethodConfigurations
        $Issues = [System.Collections.Generic.List[string]]::new()
        foreach ($Id in 'Sms','Voice','Email') {
            $C = $Configs | Where-Object { $_.id -eq $Id }
            if ($C -and $C.state -eq 'enabled') { $Issues.Add($Id) }
        }

        if ($Issues.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'SMS, Voice and Email OTP methods are all disabled.'
        } else {
            $Status = 'Failed'
            $Result = "The following weak (non phishing-resistant) MFA methods are still enabled: $($Issues -join ', ')."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML2 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'E8 ML2 - MFA'
    }
}
