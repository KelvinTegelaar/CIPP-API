function Invoke-CippTestEIDSCAPR01 {
    <#
    .SYNOPSIS
    Password Rule Settings - Password Protection Mode
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Password Rule Settings - Password Protection Mode' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Password Policy'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'BannedPasswordCheckOnPremisesMode' }).value

        if ($SettingValue -eq 'Enforce') {
            $Status = 'Passed'
            $Result = 'Password protection mode is set to Enforce'
        } else {
            $Status = 'Failed'
            $Result = @"
Password protection mode should be set to Enforce to prevent weak passwords.

**Current Configuration:**
- BannedPasswordCheckOnPremisesMode: $SettingValue

**Recommended Configuration:**
- BannedPasswordCheckOnPremisesMode: Enforce
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Password Rule Settings - Password Protection Mode' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Password Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Password Rule Settings - Password Protection Mode' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Password Policy'
    }
}
