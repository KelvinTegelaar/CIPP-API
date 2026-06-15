function Invoke-CippTestGenericTest004 {
    <#
    .SYNOPSIS
    Tenant MFA Report — full MFA posture overview for all accounts
    #>
    param($Tenant)

    try {
        $MFAData = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'

        if (-not $MFAData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest004' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No MFA state data found in the reporting database. Please sync the MFA State cache first.' -Risk 'Informational' -Name 'Tenant MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $Users = @($MFAData | Where-Object { $_.UPN })
        if ($Users.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest004' -TestType 'Identity' -Status 'Informational' -ResultMarkdown 'MFA state data was found but contained no user records.' -Risk 'Informational' -Name 'Tenant MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $TotalUsers = $Users.Count
        $MFARegistered = 0
        $MFACapable = 0
        $CoveredByCA = 0
        $CoveredBySD = 0
        $PerUserMFA = 0
        $NotProtected = 0
        $AdminCount = 0
        foreach ($u in $Users) {
            if ($u.MFARegistration -eq $true) { $MFARegistered++ }
            if ($u.MFACapable -eq $true) { $MFACapable++ }
            $isCA = $u.CoveredByCA -like 'Enforced*'
            $isSD = $u.CoveredBySD -eq $true
            $isPerUser = $u.PerUser -in @('Enforced', 'Enabled')
            if ($isCA) { $CoveredByCA++ }
            if ($isSD) { $CoveredBySD++ }
            if ($isPerUser) { $PerUserMFA++ }
            if (-not $isCA -and -not $isSD -and -not $isPerUser) { $NotProtected++ }
            if ($u.IsAdmin -eq $true) { $AdminCount++ }
        }
        $MFARegPct = if ($TotalUsers -gt 0) { [math]::Round(($MFARegistered / $TotalUsers) * 100, 1) } else { 0 }

        $Result = [System.Text.StringBuilder]::new("### Summary`n`n")
        $null = $Result.Append("| Metric | Count |`n")
        $null = $Result.Append("|--------|-------|`n")
        $null = $Result.Append("| Total Accounts | $TotalUsers |`n")
        $null = $Result.Append("| Admin Accounts | $AdminCount |`n")
        $null = $Result.Append("| Registered for MFA | $MFARegistered ($MFARegPct%) |`n")
        $null = $Result.Append("| MFA Capable | $MFACapable |`n")
        $null = $Result.Append("| Protected by Conditional Access | $CoveredByCA |`n")
        $null = $Result.Append("| Protected by Security Defaults | $CoveredBySD |`n")
        $null = $Result.Append("| Using Per-User MFA (Legacy) | $PerUserMFA |`n")
        $null = $Result.Append("| **Not Protected by Any MFA Policy** | **$NotProtected** |`n`n")

        if ($NotProtected -gt 0) {
            $null = $Result.Append("**⚠️ $NotProtected account(s) have no MFA enforcement.** These accounts are at significantly higher risk of compromise. Consider enabling Conditional Access policies to require MFA for all users.`n`n")
        }

        $null = $Result.Append("### All Accounts`n`n")
        $null = $Result.Append("| Display Name | MFA Registered | MFA Method | Protected By | Account Type |`n")
        $null = $Result.Append("|-------------|----------------|------------|--------------|--------------|`n")

        $DisplayUsers = $Users | Sort-Object DisplayName | Select-Object -First 100
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
            $AcctType = if ($User.IsAdmin -eq $true) { '🔑 Admin' } else { 'User' }
            $null = $Result.Append("| $Name | $Registered | $Methods | $Protection | $AcctType |`n")
        }

        if ($Users.Count -gt 100) {
            $null = $Result.Append("`n*Showing 100 of $($Users.Count) accounts.*`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest004' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Tenant MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest004: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest004' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Tenant MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
