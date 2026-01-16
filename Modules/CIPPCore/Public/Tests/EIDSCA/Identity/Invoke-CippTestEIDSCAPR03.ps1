function Invoke-CippTestEIDSCAPR03 {
    <#
    .SYNOPSIS
    Password Rule Settings - Enforce custom list
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR03' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Password Rule Settings - Enforce custom list' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }).value

        if ($SettingValue -eq 'True') {
            $Status = 'Passed'
            $Result = 'Custom banned password list is enforced'
        } else {
            $Status = 'Failed'
            $Result = @"
Custom banned password list should be enforced to prevent common weak passwords.

**Current Configuration:**
- EnableBannedPasswordCheck: $SettingValue

**Recommended Configuration:**
- EnableBannedPasswordCheck: True
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR03' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Password Rule Settings - Enforce custom list' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR03' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Password Rule Settings - Enforce custom list' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
    }
}
