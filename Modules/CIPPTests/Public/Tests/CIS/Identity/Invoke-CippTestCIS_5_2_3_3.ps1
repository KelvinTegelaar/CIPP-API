function Invoke-CippTestCIS_5_2_3_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.3.3) - Password protection SHALL be enabled for on-prem Active Directory
    #>
    param($Tenant)

    try {
        $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'
        $Org = Get-CIPPTestData -TenantFilter $Tenant -Type 'Organization'

        if (-not $Settings -or -not $Org) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (Settings or Organization) not found.' -Risk 'Medium' -Name 'Password protection is enabled for on-prem Active Directory' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Authentication'
            return
        }

        $OrgCfg = $Org | Select-Object -First 1
        if ($OrgCfg.onPremisesSyncEnabled -ne $true) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_3' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'Tenant is cloud-only — recommendation does not apply.' -Risk 'Medium' -Name 'Password protection is enabled for on-prem Active Directory' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Authentication'
            return
        }

        $PwdSetting = $Settings | Where-Object { $_.displayName -eq 'Password Rule Settings' -or $_.templateId -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' } | Select-Object -First 1
        $EnableForOnPrem = ($PwdSetting.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheckOnPremises' }).value
        $Mode = ($PwdSetting.values | Where-Object { $_.name -eq 'BannedPasswordCheckOnPremisesMode' }).value

        if ($EnableForOnPrem -eq 'True' -and $Mode -eq 'Enforce') {
            $Status = 'Passed'
            $Result = 'On-prem password protection is enabled in Enforce mode.'
        } else {
            $Status = 'Failed'
            $Result = "On-prem password protection is not in Enforce mode. EnableBannedPasswordCheckOnPremises: $EnableForOnPrem; Mode: $Mode."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Password protection is enabled for on-prem Active Directory' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Password protection is enabled for on-prem Active Directory' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Authentication'
    }
}
