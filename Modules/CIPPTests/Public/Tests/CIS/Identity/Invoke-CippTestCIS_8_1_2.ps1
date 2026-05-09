function Invoke-CippTestCIS_8_1_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.1.2) - Users SHALL NOT be able to send emails to a channel email address
    #>
    param($Tenant)

    try {
        $Client = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsClientConfiguration'

        if (-not $Client) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_1_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsClientConfiguration cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "Users can't send emails to a channel email address" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Cfg = $Client | Select-Object -First 1

        if ($Cfg.AllowEmailIntoChannel -eq $false) {
            $Status = 'Passed'
            $Result = 'Email-into-channel is disabled (AllowEmailIntoChannel: false).'
        } else {
            $Status = 'Failed'
            $Result = "Email-into-channel is enabled (AllowEmailIntoChannel: $($Cfg.AllowEmailIntoChannel))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_1_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "Users can't send emails to a channel email address" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_1_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Users can't send emails to a channel email address" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
