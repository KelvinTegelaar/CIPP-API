function Invoke-CippTestGenericTest005 {
    <#
    .SYNOPSIS
    Admin MFA Report — MFA posture for administrator accounts only
    #>
    param($Tenant)

    try {
        $MFAData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'MFAState'

        if (-not $MFAData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest005' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No MFA state data found in the reporting database. Please sync the MFA State cache first.' -Risk 'Informational' -Name 'Admin MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $Admins = @($MFAData | Where-Object { $_.UPN -and $_.IsAdmin -eq $true })

        if ($Admins.Count -eq 0) {
            $Result = "No administrator accounts were found in the MFA state data. This is unusual and may indicate the data needs to be re-synced."
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest005' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Admin MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $TotalAdmins = $Admins.Count
        $MFARegistered = @($Admins | Where-Object { $_.MFARegistration -eq $true }).Count
        $NotProtected = @($Admins | Where-Object { $_.CoveredByCA -notlike 'Enforced*' -and $_.CoveredBySD -ne $true -and $_.PerUser -notin @('Enforced', 'Enabled') }).Count
        $MFARegPct = if ($TotalAdmins -gt 0) { [math]::Round(($MFARegistered / $TotalAdmins) * 100, 1) } else { 0 }

        $Result = "**Total Admins:** $TotalAdmins | **MFA Registered:** $MFARegistered ($MFARegPct%)"
        if ($NotProtected -gt 0) {
            $Result += " | **⚠️ Unprotected: $NotProtected**"
        }
        $Result += "`n`n"

        if ($NotProtected -gt 0) {
            $Result += "**🔴 Critical: $NotProtected admin account(s) have no MFA enforcement.** Admin accounts without MFA are the #1 target for attackers. This should be addressed immediately.`n`n"
        } elseif ($MFARegistered -eq $TotalAdmins) {
            $Result += "**✅ All admin accounts have MFA registered and enforced.** Great job keeping your most privileged accounts secured.`n`n"
        }

        $Result += "| Display Name | MFA Registered | MFA Method | Protected By | Account Enabled |`n"
        $Result += "|-------------|----------------|------------|--------------|-----------------|`n"

        foreach ($Admin in ($Admins | Sort-Object DisplayName)) {
            $Name = $Admin.DisplayName
            $Registered = if ($Admin.MFARegistration -eq $true) { '✅ Yes' } else { '❌ No' }
            $Methods = if ($Admin.MFAMethods) {
                $MethodList = if ($Admin.MFAMethods -is [string]) {
                    try { ($Admin.MFAMethods | ConvertFrom-Json) -join ', ' } catch { $Admin.MFAMethods }
                } else { ($Admin.MFAMethods) -join ', ' }
                $MethodList -replace 'microsoftAuthenticator', 'Authenticator' -replace 'phoneAuthentication', 'Phone' -replace 'fido2', 'FIDO2' -replace 'softwareOneTimePasscode', 'Software OTP' -replace 'emailAuthentication', 'Email' -replace 'windowsHelloForBusiness', 'Windows Hello' -replace 'temporaryAccessPass', 'Temp Pass'
            } else { 'None' }
            $Protection = if ($Admin.CoveredByCA -like 'Enforced*') { "Conditional Access" }
            elseif ($Admin.CoveredBySD -eq $true) { 'Security Defaults' }
            elseif ($Admin.PerUser -in @('Enforced', 'Enabled')) { "Per-User MFA ($($Admin.PerUser))" }
            else { '❌ None' }
            $Enabled = if ($Admin.AccountEnabled -eq $true) { 'Yes' } else { 'Disabled' }
            $Result += "| $Name | $Registered | $Methods | $Protection | $Enabled |`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest005' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Admin MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest005: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest005' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Admin MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
