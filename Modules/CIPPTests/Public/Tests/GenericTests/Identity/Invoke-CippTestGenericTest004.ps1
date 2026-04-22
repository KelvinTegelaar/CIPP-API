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
        $MFARegistered = @($Users | Where-Object { $_.MFARegistration -eq $true }).Count
        $MFACapable = @($Users | Where-Object { $_.MFACapable -eq $true }).Count
        $CoveredByCA = @($Users | Where-Object { $_.CoveredByCA -like 'Enforced*' }).Count
        $CoveredBySD = @($Users | Where-Object { $_.CoveredBySD -eq $true }).Count
        $PerUserMFA = @($Users | Where-Object { $_.PerUser -in @('Enforced', 'Enabled') }).Count
        $NotProtected = @($Users | Where-Object { $_.CoveredByCA -notlike 'Enforced*' -and $_.CoveredBySD -ne $true -and $_.PerUser -notin @('Enforced', 'Enabled') }).Count
        $AdminCount = @($Users | Where-Object { $_.IsAdmin -eq $true }).Count
        $MFARegPct = if ($TotalUsers -gt 0) { [math]::Round(($MFARegistered / $TotalUsers) * 100, 1) } else { 0 }

        $Result = "### Summary`n`n"
        $Result += "| Metric | Count |`n"
        $Result += "|--------|-------|`n"
        $Result += "| Total Accounts | $TotalUsers |`n"
        $Result += "| Admin Accounts | $AdminCount |`n"
        $Result += "| Registered for MFA | $MFARegistered ($MFARegPct%) |`n"
        $Result += "| MFA Capable | $MFACapable |`n"
        $Result += "| Protected by Conditional Access | $CoveredByCA |`n"
        $Result += "| Protected by Security Defaults | $CoveredBySD |`n"
        $Result += "| Using Per-User MFA (Legacy) | $PerUserMFA |`n"
        $Result += "| **Not Protected by Any MFA Policy** | **$NotProtected** |`n`n"

        if ($NotProtected -gt 0) {
            $Result += "**⚠️ $NotProtected account(s) have no MFA enforcement.** These accounts are at significantly higher risk of compromise. Consider enabling Conditional Access policies to require MFA for all users.`n`n"
        }

        $Result += "### All Accounts`n`n"
        $Result += "| Display Name | MFA Registered | MFA Method | Protected By | Account Type |`n"
        $Result += "|-------------|----------------|------------|--------------|--------------|`n"

        $DisplayUsers = $Users | Sort-Object DisplayName | Select-Object -First 100
        foreach ($User in $DisplayUsers) {
            $Name = $User.DisplayName
            $Registered = if ($User.MFARegistration -eq $true) { '✅ Yes' } else { '❌ No' }
            $Methods = if ($User.MFAMethods) {
                $MethodList = if ($User.MFAMethods -is [string]) {
                    try { ($User.MFAMethods | ConvertFrom-Json) -join ', ' } catch { $User.MFAMethods }
                } else { ($User.MFAMethods) -join ', ' }
                $MethodList -replace 'microsoftAuthenticator', 'Authenticator' -replace 'phoneAuthentication', 'Phone' -replace 'fido2', 'FIDO2' -replace 'softwareOneTimePasscode', 'Software OTP' -replace 'emailAuthentication', 'Email' -replace 'windowsHelloForBusiness', 'Windows Hello' -replace 'temporaryAccessPass', 'Temp Pass'
            } else { 'None' }
            $Protection = if ($User.CoveredByCA -like 'Enforced*') { "Conditional Access" }
            elseif ($User.CoveredBySD -eq $true) { 'Security Defaults' }
            elseif ($User.PerUser -in @('Enforced', 'Enabled')) { "Per-User MFA ($($User.PerUser))" }
            else { '❌ None' }
            $AcctType = if ($User.IsAdmin -eq $true) { '🔑 Admin' } else { 'User' }
            $Result += "| $Name | $Registered | $Methods | $Protection | $AcctType |`n"
        }

        if ($Users.Count -gt 100) {
            $Result += "`n*Showing 100 of $($Users.Count) accounts.*`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest004' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Tenant MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest004: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest004' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Tenant MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
