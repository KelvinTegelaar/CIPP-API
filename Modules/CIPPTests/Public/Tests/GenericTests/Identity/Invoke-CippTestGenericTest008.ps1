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

        $Result = [System.Text.StringBuilder]::new()

        if ($PerUserMFAUsers.Count -eq 0) {
            $null = $Result.Append("**✅ No accounts are using legacy Per-User MFA.** Your tenant is not relying on the deprecated per-user MFA enforcement method.`n`n")
            $null = $Result.Append("Make sure your accounts are protected by Conditional Access policies or Security Defaults instead.")
            Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest008' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Legacy Per-User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
            return
        }

        $EnforcedCount = 0
        $EnabledCount = 0
        $AdminsAffected = 0
        foreach ($u in $PerUserMFAUsers) {
            if ($u.PerUser -eq 'Enforced') { $EnforcedCount++ }
            if ($u.PerUser -eq 'Enabled') { $EnabledCount++ }
            if ($u.IsAdmin -eq $true) { $AdminsAffected++ }
        }

        $null = $Result.Append("### Current Status`n`n")
        $null = $Result.Append("**⚠️ $($PerUserMFAUsers.Count) account(s) are still using legacy Per-User MFA.**`n`n")
        $null = $Result.Append("| Status | Count |`n")
        $null = $Result.Append("|--------|-------|`n")
        $null = $Result.Append("| Per-User MFA Enforced | $EnforcedCount |`n")
        $null = $Result.Append("| Per-User MFA Enabled | $EnabledCount |`n")
        if ($AdminsAffected -gt 0) {
            $null = $Result.Append("| Admin Accounts Affected | $AdminsAffected |`n")
        }
        $null = $Result.Append("`n")

        $null = $Result.Append("### Accounts Using Per-User MFA`n`n")
        $null = $Result.Append("The following accounts should be migrated to Conditional Access policies:`n`n")
        $null = $Result.Append("| Display Name | Per-User MFA Status | Also Covered by CA | Account Type | Licensed |`n")
        $null = $Result.Append("|-------------|--------------------|--------------------|--------------|----------|`n")

        foreach ($User in ($PerUserMFAUsers | Sort-Object DisplayName)) {
            $Name = $User.DisplayName
            $PerUserStatus = $User.PerUser
            $CAProtected = if ($User.CoveredByCA -like 'Enforced*') { '✅ Yes' } else { '❌ No' }
            $AcctType = if ($User.IsAdmin -eq $true) { '🔑 Admin' } else { 'User' }
            $Licensed = if ($User.isLicensed -eq $true) { 'Yes' } else { 'No' }
            $null = $Result.Append("| $Name | $PerUserStatus | $CAProtected | $AcctType | $Licensed |`n")
        }

        $null = $Result.Append("`n### Recommended Migration Steps`n`n")
        $null = $Result.Append("1. **Create a Conditional Access policy** that requires MFA for all users (or start with admins)`n")
        $null = $Result.Append("2. **Verify** the Conditional Access policy is working correctly for affected users`n")
        $null = $Result.Append("3. **Disable Per-User MFA** for each account listed above once confirmed`n")
        $null = $Result.Append("4. **Test sign-in** to confirm users can still authenticate properly`n")

        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest008' -TestType 'Identity' -Status 'Informational' -ResultMarkdown $Result -Risk 'Informational' -Name 'Legacy Per-User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test GenericTest008: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'GenericTest008' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Informational' -Name 'Legacy Per-User MFA Report' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant Overview'
    }
}
