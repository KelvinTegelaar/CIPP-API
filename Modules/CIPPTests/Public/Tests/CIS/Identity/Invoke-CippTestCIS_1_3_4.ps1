function Invoke-CippTestCIS_1_3_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.3.4) - 'User owned apps and services' SHALL be restricted
    #>
    param($Tenant)

    try {
        $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Settings cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "'User owned apps and services' is restricted" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
            return
        }

        $AppsAndServices = $Settings | Where-Object { $_.id -eq 'appsAndServices' -or $_.PSObject.Properties.Name -contains 'isOfficeStoreEnabled' } | Select-Object -First 1

        if (-not $AppsAndServices) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'appsAndServices settings not present in the Settings cache.' -Risk 'Medium' -Name "'User owned apps and services' is restricted" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
            return
        }

        $StoreEnabled = $AppsAndServices.isOfficeStoreEnabled
        $TrialsEnabled = $AppsAndServices.isAppAndServicesTrialEnabled

        if ($StoreEnabled -eq $false -and $TrialsEnabled -eq $false) {
            $Status = 'Passed'
            $Result = "Office Store and trials are both disabled.`n`n- isOfficeStoreEnabled: false`n- isAppAndServicesTrialEnabled: false"
        } else {
            $Status = 'Failed'
            $Result = "User owned apps and services are not fully restricted.`n`n- isOfficeStoreEnabled: $StoreEnabled (expected: false)`n- isAppAndServicesTrialEnabled: $TrialsEnabled (expected: false)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "'User owned apps and services' is restricted" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "'User owned apps and services' is restricted" -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
    }
}
