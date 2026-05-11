function Invoke-CippTestCIS_8_4_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.4.1) - App permission policies SHALL be configured
    #>
    param($Tenant)

    try {
        $AppPerms = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsAppPermissionPolicy'

        if (-not $AppPerms) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_4_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsAppPermissionPolicy cache not found.' -Risk 'Medium' -Name 'App permission policies are configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }

        $Global = $AppPerms | Where-Object { $_.Identity -eq 'Global' } | Select-Object -First 1
        if (-not $Global) { $Global = $AppPerms | Select-Object -First 1 }

        $ThirdParty = $Global.GlobalCatalogAppsType ?? $Global.DefaultCatalogAppsType
        $Restricted = $ThirdParty -in @('BlockedAppList', 'AllowedAppList', 'BlockAllApps')

        if ($Restricted) {
            $Status = 'Passed'
            $Result = "Teams App Permission Policy restricts third-party apps (mode: $ThirdParty)."
        } else {
            $Status = 'Failed'
            $Result = "Teams App Permission Policy allows all third-party apps (mode: $ThirdParty). Set to BlockedAppList, AllowedAppList, or BlockAllApps."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_4_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'App permission policies are configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_4_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'App permission policies are configured' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
