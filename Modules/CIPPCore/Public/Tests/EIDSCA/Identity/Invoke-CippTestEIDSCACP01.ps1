function Invoke-CippTestEIDSCACP01 {
    <#
    .SYNOPSIS
    Consent Policy Settings - Group owner consent for apps accessing data
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Consent Policy Settings - Group owner consent for apps accessing data' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Consent Policy'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'EnableGroupSpecificConsent' }).value

        if ($SettingValue -eq 'False') {
            $Status = 'Passed'
            $Result = 'Group owner consent for apps is disabled'
        } else {
            $Status = 'Failed'
            $Result = @"
Group owner consent should be disabled to prevent unauthorized app permissions.

**Current Configuration:**
- EnableGroupSpecificConsent: $SettingValue

**Recommended Configuration:**
- EnableGroupSpecificConsent: False
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Consent Policy Settings - Group owner consent for apps accessing data' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Consent Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Consent Policy Settings - Group owner consent for apps accessing data' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Consent Policy'
    }
}
