function Invoke-CippTestGenericTest008 {
    <#
    .SYNOPSIS
    Legacy Per-User MFA Report — accounts still using per-user MFA enforcement
    #>
    param($Tenant)

    try {
        $MFAData = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'

        if (-not $MFAData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest008' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No MFA state data found in the reporting database. Please sync the MFA State cache first.' -Risk 'Informational' -Name 'Legacy Per-User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $AllUsers = @($MFAData | Where-Object { $_.UPN })
        $PerUserMFAUsers = @($AllUsers | Where-Object { $_.PerUser -in @('Enforced', 'Enabled') })

        $Result = ""

        if ($PerUserMFAUsers.Count -eq 0) {
            $Result += "**✅ No accounts are using legacy Per-User MFA.** Your tenant is not relying on the deprecated per-user MFA enforcement method.`n`n"
            $Result += "Make sure your accounts are protected by Conditional Access policies or Security Defaults instead."
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest008' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Legacy Per-User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $EnforcedCount = @($PerUserMFAUsers | Where-Object { $_.PerUser -eq 'Enforced' }).Count
        $EnabledCount = @($PerUserMFAUsers | Where-Object { $_.PerUser -eq 'Enabled' }).Count
        $AdminsAffected = @($PerUserMFAUsers | Where-Object { $_.IsAdmin -eq $true }).Count

        $Result += "### Current Status`n`n"
        $Result += "**⚠️ $($PerUserMFAUsers.Count) account(s) are still using legacy Per-User MFA.**`n`n"
        $Result += "| Status | Count |`n"
        $Result += "|--------|-------|`n"
        $Result += "| Per-User MFA Enforced | $EnforcedCount |`n"
        $Result += "| Per-User MFA Enabled | $EnabledCount |`n"
        if ($AdminsAffected -gt 0) {
            $Result += "| Admin Accounts Affected | $AdminsAffected |`n"
        }
        $Result += "`n"

        $Result += "### Accounts Using Per-User MFA`n`n"
        $Result += "The following accounts should be migrated to Conditional Access policies:`n`n"
        $Result += "| Display Name | Per-User MFA Status | Also Covered by CA | Account Type | Licensed |`n"
        $Result += "|-------------|--------------------|--------------------|--------------|----------|`n"

        foreach ($User in ($PerUserMFAUsers | Sort-Object DisplayName)) {
            $Name = $User.DisplayName
            $PerUserStatus = $User.PerUser
            $CAProtected = if ($User.CoveredByCA -like 'Enforced*') { '✅ Yes' } else { '❌ No' }
            $AcctType = if ($User.IsAdmin -eq $true) { '🔑 Admin' } else { 'User' }
            $Licensed = if ($User.isLicensed -eq $true) { 'Yes' } else { 'No' }
            $Result += "| $Name | $PerUserStatus | $CAProtected | $AcctType | $Licensed |`n"
        }

        $Result += "`n### Recommended Migration Steps`n`n"
        $Result += "1. **Create a Conditional Access policy** that requires MFA for all users (or start with admins)`n"
        $Result += "2. **Verify** the Conditional Access policy is working correctly for affected users`n"
        $Result += "3. **Disable Per-User MFA** for each account listed above once confirmed`n"
        $Result += "4. **Test sign-in** to confirm users can still authenticate properly`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest008' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Legacy Per-User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest008: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest008' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Legacy Per-User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
