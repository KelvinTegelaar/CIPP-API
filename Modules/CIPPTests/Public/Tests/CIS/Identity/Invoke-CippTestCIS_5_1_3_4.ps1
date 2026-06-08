function Invoke-CippTestCIS_5_1_3_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.1.3.4) - 'Users can create Microsoft 365 groups in Azure portals, API or PowerShell' SHALL be set to 'No'
    #>
    param($Tenant)

    try {
        $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Settings cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Users cannot create Microsoft 365 groups in Azure portals, API or PowerShell' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Management'
            return
        }

        # Group.Unified directory settings template
        $GroupSetting = $Settings | Where-Object { $_.templateId -eq '62375ab9-6b52-47ed-826b-58e47e0e304b' -or $_.displayName -eq 'Group.Unified' } | Select-Object -First 1

        if (-not $GroupSetting) {
            # No Group.Unified settings object means defaults are in effect (EnableGroupCreation = true), which is non-compliant.
            $Status = 'Failed'
            $Result = 'No Group.Unified directory settings object exists, so the default applies (users can create Microsoft 365 groups). Set Users can create Microsoft 365 groups to No.'
        } else {
            $EnableGroupCreation = ($GroupSetting.values | Where-Object { $_.name -eq 'EnableGroupCreation' }).value

            if ("$EnableGroupCreation" -eq 'false') {
                $Status = 'Passed'
                $Result = 'Users cannot create Microsoft 365 groups (EnableGroupCreation: false).'
            } else {
                $Status = 'Failed'
                $Result = "Users can create Microsoft 365 groups (EnableGroupCreation: $EnableGroupCreation)."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users cannot create Microsoft 365 groups in Azure portals, API or PowerShell' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users cannot create Microsoft 365 groups in Azure portals, API or PowerShell' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Management'
    }
}
