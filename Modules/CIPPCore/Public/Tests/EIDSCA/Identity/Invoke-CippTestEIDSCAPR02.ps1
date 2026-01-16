function Invoke-CippTestEIDSCAPR02 {
    <#
    .SYNOPSIS
    Password Rule Settings - Enable password protection on Windows Server Active Directory
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR02' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Password Rule Settings - Enable password protection on Windows Server Active Directory' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Password Policy'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheckOnPremises' }).value

        if ($SettingValue -eq 'True') {
            $Status = 'Passed'
            $Result = 'Password protection is enabled for on-premises Active Directory'
        } else {
            $Status = 'Failed'
            $Result = @"
Password protection should be enabled for on-premises Active Directory to prevent weak passwords.

**Current Configuration:**
- EnableBannedPasswordCheckOnPremises: $SettingValue

**Recommended Configuration:**
- EnableBannedPasswordCheckOnPremises: True
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR02' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Password Rule Settings - Enable password protection on Windows Server Active Directory' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Password Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR02' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Password Rule Settings - Enable password protection on Windows Server Active Directory' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Password Policy'
    }
}
