function Invoke-CippTestCIS_5_1_8_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.8.1) - Password hash sync SHALL be enabled for hybrid deployments (Manual)
    #>
    param($Tenant)

    try {
        $Org = Get-CIPPTestData -TenantFilter $Tenant -Type 'Organization'
        $Domains = Get-CIPPTestData -TenantFilter $Tenant -Type 'Domains'

        if (-not $Org -or -not $Domains) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_8_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Organization or Domains) not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Password hash sync is enabled for hybrid deployments' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Identity'
            return
        }

        $OrgCfg = $Org | Select-Object -First 1
        $IsHybrid = $OrgCfg.onPremisesSyncEnabled -eq $true

        if (-not $IsHybrid) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_8_1' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'Tenant is cloud-only (onPremisesSyncEnabled: false) — recommendation does not apply.' -Risk 'Medium' -Name 'Password hash sync is enabled for hybrid deployments' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Identity'
            return
        }

        # PHS state isn't directly readable via Graph; surface as Skipped
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_8_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown @'
Tenant has on-prem sync enabled, but password hash sync (PHS) state is not exposed via Graph and must be verified manually.

```powershell
# On the Entra Connect Sync server:
Get-ADSyncAADCompanyFeature
```

`PasswordHashSync` should be `True`.
'@ -Risk 'Medium' -Name 'Password hash sync is enabled for hybrid deployments' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Identity'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_8_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Password hash sync is enabled for hybrid deployments' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Identity'
    }
}
