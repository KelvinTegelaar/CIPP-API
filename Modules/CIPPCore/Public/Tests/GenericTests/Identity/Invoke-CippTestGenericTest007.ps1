function Invoke-CippTestGenericTest007 {
    <#
    .SYNOPSIS
    Licensed User MFA Report — MFA posture for licensed users only
    #>
    param($Tenant)

    try {
        $MFAData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'MFAState'

        if (-not $MFAData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest007' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No MFA state data found in the reporting database. Please sync the MFA State cache first.' -Risk 'Informational' -Name 'Licensed User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $LicensedUsers = @($MFAData | Where-Object { $_.UPN -and $_.isLicensed -eq $true })

        if ($LicensedUsers.Count -eq 0) {
            $Result = "No licensed user accounts were found in the MFA state data. This may indicate no licenses have been assigned or the data needs to be re-synced."
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest007' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Licensed User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $TotalUsers = $LicensedUsers.Count
        $MFARegistered = @($LicensedUsers | Where-Object { $_.MFARegistration -eq $true }).Count
        $NotProtected = @($LicensedUsers | Where-Object { $_.CoveredByCA -notlike 'Enforced*' -and $_.CoveredBySD -ne $true -and $_.PerUser -notin @('Enforced', 'Enabled') }).Count
        $Admins = @($LicensedUsers | Where-Object { $_.IsAdmin -eq $true }).Count
        $MFARegPct = if ($TotalUsers -gt 0) { [math]::Round(($MFARegistered / $TotalUsers) * 100, 1) } else { 0 }

        $Result = "**Licensed Users:** $TotalUsers | **Admins among them:** $Admins | **MFA Registered:** $MFARegistered ($MFARegPct%)"
        if ($NotProtected -gt 0) {
            $Result += " | **Unprotected: $NotProtected**"
        }
        $Result += "`n`n"

        if ($NotProtected -gt 0) {
            $Result += "**⚠️ $NotProtected licensed user(s) have no MFA enforcement.** These accounts have access to company data and email but are not protected by any MFA policy.`n`n"
        }

        $Result += "| Display Name | Role | MFA Registered | MFA Method | Protected By |`n"
        $Result += "|-------------|------|----------------|------------|--------------|`n"

        $DisplayUsers = $LicensedUsers | Sort-Object DisplayName | Select-Object -First 100
        foreach ($User in $DisplayUsers) {
            $Name = $User.DisplayName
            $Role = if ($User.IsAdmin -eq $true) { '🔑 Admin' } else { 'User' }
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
            $Result += "| $Name | $Role | $Registered | $Methods | $Protection |`n"
        }

        if ($LicensedUsers.Count -gt 100) {
            $Result += "`n*Showing 100 of $($LicensedUsers.Count) licensed user accounts.*`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest007' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Licensed User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest007: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest007' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Licensed User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
