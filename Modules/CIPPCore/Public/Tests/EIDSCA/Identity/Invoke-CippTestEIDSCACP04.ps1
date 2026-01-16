function Invoke-CippTestEIDSCACP04 {
    <#
    .SYNOPSIS
    Consent Policy Settings - Users can request admin consent
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP04' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Consent Policy Settings - Users can request admin consent' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'EnableAdminConsentRequests' }).value

        if ($SettingValue -eq 'true') {
            $Status = 'Passed'
            $Result = 'Users can request admin consent for apps'
        } else {
            $Status = 'Failed'
            $Result = @"
Users should be able to request admin consent to enable proper app approval workflows.

**Current Configuration:**
- EnableAdminConsentRequests: $SettingValue

**Recommended Configuration:**
- EnableAdminConsentRequests: true
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP04' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Consent Policy Settings - Users can request admin consent' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCACP04' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Consent Policy Settings - Users can request admin consent' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Consent Policy'
    }
}
