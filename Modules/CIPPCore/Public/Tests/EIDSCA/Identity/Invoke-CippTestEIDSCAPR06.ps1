function Invoke-CippTestEIDSCAPR06 {
    <#
    .SYNOPSIS
    Password Rule Settings - Lockout threshold
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR06' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Password Rule Settings - Lockout threshold' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'LockoutThreshold' }).value

        if ([int]$SettingValue -le 10) {
            $Status = 'Passed'
            $Result = "Lockout threshold is set to $SettingValue failed attempts (maximum 10 attempts recommended)"
        } else {
            $Status = 'Failed'
            $Result = @"
Lockout threshold should be 10 or fewer failed attempts to protect against brute force attacks.

**Current Configuration:**
- LockoutThreshold: $SettingValue

**Recommended Configuration:**
- LockoutThreshold: 10 or fewer
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR06' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Password Rule Settings - Lockout threshold' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAPR06' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Password Rule Settings - Lockout threshold' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Policy'
    }
}
