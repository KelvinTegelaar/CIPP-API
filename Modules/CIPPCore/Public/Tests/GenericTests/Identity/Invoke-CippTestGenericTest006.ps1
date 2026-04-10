function Invoke-CippTestGenericTest006 {
    <#
    .SYNOPSIS
    User MFA Report — MFA posture for standard (non-admin) user accounts
    #>
    param($Tenant)

    try {
        $MFAData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'MFAState'

        if (-not $MFAData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest006' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No MFA state data found in the reporting database. Please sync the MFA State cache first.' -Risk 'Informational' -Name 'User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $StandardUsers = @($MFAData | Where-Object { $_.UPN -and $_.IsAdmin -ne $true })

        if ($StandardUsers.Count -eq 0) {
            $Result = "No standard (non-admin) user accounts were found in the MFA state data."
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest006' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $TotalUsers = $StandardUsers.Count
        $MFARegistered = @($StandardUsers | Where-Object { $_.MFARegistration -eq $true }).Count
        $NotProtected = @($StandardUsers | Where-Object { $_.CoveredByCA -notlike 'Enforced*' -and $_.CoveredBySD -ne $true -and $_.PerUser -notin @('Enforced', 'Enabled') }).Count
        $MFARegPct = if ($TotalUsers -gt 0) { [math]::Round(($MFARegistered / $TotalUsers) * 100, 1) } else { 0 }

        $Result = "**Total Users:** $TotalUsers | **MFA Registered:** $MFARegistered ($MFARegPct%)"
        if ($NotProtected -gt 0) {
            $Result += " | **Unprotected: $NotProtected**"
        }
        $Result += "`n`n"

        if ($NotProtected -gt 0) {
            $Result += "**⚠️ $NotProtected user account(s) have no MFA enforcement.** Consider enabling a Conditional Access policy that requires MFA for all users.`n`n"
        }

        $Result += "| Display Name | MFA Registered | MFA Method | Protected By | User Type |`n"
        $Result += "|-------------|----------------|------------|--------------|-----------|`n"

        $DisplayUsers = $StandardUsers | Sort-Object DisplayName | Select-Object -First 100
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
            $UserType = if ($User.UserType -eq 'Guest') { 'Guest' } else { 'Member' }
            $Result += "| $Name | $Registered | $Methods | $Protection | $UserType |`n"
        }

        if ($StandardUsers.Count -gt 100) {
            $Result += "`n*Showing 100 of $($StandardUsers.Count) user accounts.*`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest006' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest006: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest006' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
