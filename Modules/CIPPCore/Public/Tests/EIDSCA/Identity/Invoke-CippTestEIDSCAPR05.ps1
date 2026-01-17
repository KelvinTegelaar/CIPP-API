function Invoke-CippTestEIDSCAPR05 {
    <#
    .SYNOPSIS
    Password Rule Settings - Lockout duration in seconds
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR05' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Password Rule Settings - Lockout duration in seconds' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'LockoutDurationInSeconds' }).value

        if ([int]$SettingValue -ge 60) {
            $Status = 'Passed'
            $Result = "Lockout duration is set to $SettingValue seconds (minimum 60 seconds required)"
        } else {
            $Status = 'Failed'
            $Result = @"
Lockout duration should be at least 60 seconds to protect against brute force attacks.

**Current Configuration:**
- LockoutDurationInSeconds: $SettingValue

**Recommended Configuration:**
- LockoutDurationInSeconds: 60 or greater
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR05' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Password Rule Settings - Lockout duration in seconds' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR05' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Password Rule Settings - Lockout duration in seconds' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
    }
}
