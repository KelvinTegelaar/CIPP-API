function Invoke-CippTestCIS_4_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (4.1) - Devices without a compliance policy SHALL be marked 'not compliant'
    #>
    param($Tenant)

    try {
        $DeviceSettings = Get-CIPPTestData -TenantFilter $Tenant -Type 'DeviceSettings'

        if (-not $DeviceSettings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_4_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DeviceSettings cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "Devices without a compliance policy are marked 'not compliant'" -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
            return
        }

        $Cfg = $DeviceSettings | Select-Object -First 1

        if ($Cfg.secureByDefault -eq $true) {
            $Status = 'Passed'
            $Result = 'Devices without a compliance policy are marked Not compliant (secureByDefault: true).'
        } else {
            $Status = 'Failed'
            $Result = "Devices without a compliance policy are marked Compliant by default (secureByDefault: $($Cfg.secureByDefault))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_4_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "Devices without a compliance policy are marked 'not compliant'" -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_4_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Devices without a compliance policy are marked 'not compliant'" -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
    }
}
