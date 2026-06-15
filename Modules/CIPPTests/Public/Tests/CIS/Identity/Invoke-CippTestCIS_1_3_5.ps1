function Invoke-CippTestCIS_1_3_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (1.3.5) - Internal phishing protection for Forms SHALL be enabled
    #>
    param($Tenant)

    try {
        $Forms = Get-CIPPTestData -TenantFilter $Tenant -Type 'FormsSettings'

        if (-not $Forms) {
            $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'
            $Forms = $Settings | Where-Object { $_.PSObject.Properties.Name -contains 'isInOrgFormsPhishingScanEnabled' } | Select-Object -First 1
        }

        if (-not $Forms) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Forms phishing scan setting not in cache. Please refresh FormsSettings cache for this tenant.' -Risk 'Medium' -Name 'Internal phishing protection for Forms is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Phishing Protection'
            return
        }

        if ($Forms.isInOrgFormsPhishingScanEnabled -eq $true) {
            $Status = 'Passed'
            $Result = 'Internal Forms phishing scan is enabled.'
        } else {
            $Status = 'Failed'
            $Result = "Forms phishing scan is disabled (isInOrgFormsPhishingScanEnabled: $($Forms.isInOrgFormsPhishingScanEnabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Internal phishing protection for Forms is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Phishing Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Internal phishing protection for Forms is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Phishing Protection'
    }
}
