function Invoke-CippTestCIS_5_2_3_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.3.4) - All member users SHALL be 'MFA capable'
    #>
    param($Tenant)

    try {
        $Reg = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Reg -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (UserRegistrationDetails or Users) not found.' -Risk 'High' -Name "All member users are 'MFA capable'" -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication'
            return
        }

        $Members = $Users | Where-Object { $_.userType -eq 'Member' -and $_.accountEnabled -eq $true }
        $NotCapable = @()
        foreach ($U in $Members) {
            $R = $Reg | Where-Object { $_.id -eq $U.id -or $_.userPrincipalName -eq $U.userPrincipalName } | Select-Object -First 1
            if (-not $R -or $R.isMfaCapable -ne $true) {
                $NotCapable += $U
            }
        }

        if ($NotCapable.Count -eq 0) {
            $Status = 'Passed'
            $Result = "All $($Members.Count) enabled member users are MFA capable."
        } else {
            $Status = 'Failed'
            $Result = "$($NotCapable.Count) of $($Members.Count) enabled member user(s) are not MFA capable.`n`n"
            $Result += ($NotCapable | Select-Object -First 25 | ForEach-Object { "- $($_.userPrincipalName)" }) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name "All member users are 'MFA capable'" -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name "All member users are 'MFA capable'" -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Authentication'
    }
}
