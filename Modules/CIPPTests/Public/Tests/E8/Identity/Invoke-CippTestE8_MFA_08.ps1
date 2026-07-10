function Invoke-CippTestE8_MFA_08 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML3) - All member users have a phishing-resistant method registered
    #>
    param($Tenant)

    $TestId = 'E8_MFA_08'
    $Name = 'All member users have a phishing-resistant authentication method registered'

    try {
        $Reg = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Reg -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (UserRegistrationDetails or Users) not found.' -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML3 - MFA'
            return
        }

        $MemberIds = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]($Users | Where-Object { $_.accountEnabled -eq $true -and $_.userType -ne 'Guest' }).id)

        if ($MemberIds.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No enabled member users found.' -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML3 - MFA'
            return
        }

        $PhishMethods = @('fido2SecurityKey','windowsHelloForBusiness','x509CertificateSingleFactor','x509CertificateMultiFactor','passKeyDeviceBound','passKeyDeviceBoundAuthenticator','passKeyDeviceBoundWindowsHello')
        $Total = 0; $NonCompliant = 0
        foreach ($R in $Reg | Where-Object { $MemberIds.Contains($_.id) }) {
            $Total++
            $HasPhish = $false
            foreach ($M in $R.methodsRegistered) { if ($PhishMethods -contains $M) { $HasPhish = $true; break } }
            if (-not $HasPhish) { $NonCompliant++ }
        }

        if ($NonCompliant -eq 0) {
            $Status = 'Passed'
            $Result = "All $Total enabled member users have a phishing-resistant method registered."
        } else {
            $Status = 'Failed'
            $Result = "$NonCompliant of $Total enabled member users have no phishing-resistant authentication method registered (FIDO2, Windows Hello for Business, X509 cert, or device-bound passkey)."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML3 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'High' -ImplementationEffort 'High' -Category 'E8 ML3 - MFA'
    }
}
