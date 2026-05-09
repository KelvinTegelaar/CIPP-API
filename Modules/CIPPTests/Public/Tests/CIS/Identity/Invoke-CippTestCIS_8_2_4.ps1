function Invoke-CippTestCIS_8_2_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.2.4) - Organization SHALL NOT communicate with accounts in trial Teams tenants
    #>
    param($Tenant)

    try {
        $Federation = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTenantFederationConfiguration'

        if (-not $Federation) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTenantFederationConfiguration cache not found.' -Risk 'High' -Name 'The organization cannot communicate with accounts in trial Teams tenants' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $Federation | Select-Object -First 1

        if ($Cfg.AllowTeamsConsumer -eq $false) {
            $Status = 'Passed'
            $Result = 'Trial Teams tenant communication is blocked (AllowTeamsConsumer: false).'
        } else {
            $Status = 'Failed'
            $Result = "Trial Teams tenant communication is allowed (AllowTeamsConsumer: $($Cfg.AllowTeamsConsumer))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'The organization cannot communicate with accounts in trial Teams tenants' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_2_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'The organization cannot communicate with accounts in trial Teams tenants' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
