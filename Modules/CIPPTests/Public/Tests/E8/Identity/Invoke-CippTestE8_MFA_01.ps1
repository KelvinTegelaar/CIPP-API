function Invoke-CippTestE8_MFA_01 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (MFA, ML1) - All member users are MFA capable
    #>
    param($Tenant)

    $TestId = 'E8_MFA_01'
    $Name = 'All member users are registered for MFA'

    try {
        $Reg = Get-CIPPTestData -TenantFilter $Tenant -Type 'UserRegistrationDetails'
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'

        if (-not $Reg -or -not $Users) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (UserRegistrationDetails or Users) not found. Please refresh the cache for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
            return
        }

        $RegByUpn = @{}
        foreach ($R in ($Reg | Where-Object { $_.userPrincipalName })) {
            $RegByUpn[$R.userPrincipalName.ToLower()] = $R
        }

        $MemberUsers = $Users | Where-Object { $_.accountEnabled -eq $true -and $_.userType -ne 'Guest' }
        $NotMfaCapable = foreach ($U in $MemberUsers) {
            $R = $RegByUpn[[string]$U.userPrincipalName.ToLower()]
            if (-not $R -or $R.isMfaCapable -ne $true) { $U }
        }

        if (-not $NotMfaCapable) {
            $Status = 'Passed'
            $Result = "All $($MemberUsers.Count) enabled member users are MFA capable."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($NotMfaCapable.Count) of $($MemberUsers.Count) enabled member users are not MFA capable:`n`n")
            $null = $Sb.Append("| UPN | Display Name |`n| :-- | :----------- |`n")
            foreach ($U in ($NotMfaCapable | Select-Object -First 50)) {
                $null = $Sb.Append("| $($U.userPrincipalName) | $($U.displayName) |`n")
            }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'E8 ML1 - MFA'
    }
}
