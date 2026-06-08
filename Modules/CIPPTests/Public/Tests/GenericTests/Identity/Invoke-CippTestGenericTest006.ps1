function Invoke-CippTestGenericTest006 {
    <#
    .SYNOPSIS
    User MFA Report — MFA posture for standard (non-admin) user accounts
    #>
    param($Tenant)

    try {
        $MFAData = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'

        if (-not $MFAData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest006' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No MFA state data found in the reporting database. Please sync the MFA State cache first.' -Risk 'Informational' -Name 'User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $StandardUsers = @($MFAData | Where-Object { $_.UPN -and $_.IsAdmin -ne $true })

        if ($StandardUsers.Count -eq 0) {
            $Result = [System.Text.StringBuilder]::new("No standard (non-admin) user accounts were found in the MFA state data.")
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest006' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $TotalUsers = $StandardUsers.Count
        $MFARegistered = 0
        $NotProtected = 0
        foreach ($u in $StandardUsers) {
            if ($u.MFARegistration -eq $true) { $MFARegistered++ }
            if ($u.CoveredByCA -notlike 'Enforced*' -and $u.CoveredBySD -ne $true -and $u.PerUser -notin @('Enforced', 'Enabled')) { $NotProtected++ }
        }
        $MFARegPct = if ($TotalUsers -gt 0) { [math]::Round(($MFARegistered / $TotalUsers) * 100, 1) } else { 0 }

        $Result = [System.Text.StringBuilder]::new("**Total Users:** $TotalUsers | **MFA Registered:** $MFARegistered ($MFARegPct%)")
        if ($NotProtected -gt 0) {
            $null = $Result.Append(" | **Unprotected: $NotProtected**")
        }
        $null = $Result.Append("`n`n")

        if ($NotProtected -gt 0) {
            $null = $Result.Append("**⚠️ $NotProtected user account(s) have no MFA enforcement.** Consider enabling a Conditional Access policy that requires MFA for all users.`n`n")
        }

        $null = $Result.Append("| Display Name | MFA Registered | MFA Method | Protected By | User Type |`n")
        $null = $Result.Append("|-------------|----------------|------------|--------------|-----------|`n")

        $DisplayUsers = $StandardUsers | Sort-Object DisplayName | Select-Object -First 100
        foreach ($User in $DisplayUsers) {
            $Name = ($User.DisplayName -replace '\|', '\|')
            $Registered = if ($User.MFARegistration -eq $true) { '✅ Yes' } else { '❌ No' }
            $Methods = if ($User.MFAMethods) {
                $MethodList = if ($User.MFAMethods -is [string]) {
                    try { ($User.MFAMethods | ConvertFrom-Json) -join ', ' } catch { $User.MFAMethods }
                } else { ($User.MFAMethods) -join ', ' }
                ($MethodList -replace 'microsoftAuthenticator', 'Authenticator' -replace 'phoneAuthentication', 'Phone' -replace 'fido2', 'FIDO2' -replace 'softwareOneTimePasscode', 'Software OTP' -replace 'emailAuthentication', 'Email' -replace 'windowsHelloForBusiness', 'Windows Hello' -replace 'temporaryAccessPass', 'Temp Pass') -replace '\|', '\|'
            } else { 'None' }
            $Protection = if ($User.CoveredByCA -like 'Enforced*') { "Conditional Access" }
            elseif ($User.CoveredBySD -eq $true) { 'Security Defaults' }
            elseif ($User.PerUser -in @('Enforced', 'Enabled')) { "Per-User MFA ($($User.PerUser))" }
            else { '❌ None' }
            $UserType = if ($User.UserType -eq 'Guest') { 'Guest' } else { 'Member' }
            $null = $Result.Append("| $Name | $Registered | $Methods | $Protection | $UserType |`n")
        }

        if ($StandardUsers.Count -gt 100) {
            $null = $Result.Append("`n*Showing 100 of $($StandardUsers.Count) user accounts.*`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest006' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest006: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest006' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
