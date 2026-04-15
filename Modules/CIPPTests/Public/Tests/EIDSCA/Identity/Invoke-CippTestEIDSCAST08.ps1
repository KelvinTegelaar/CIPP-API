function Invoke-CippTestEIDSCAST08 {
    <#
    .SYNOPSIS
    Classification and M365 Groups - Allow Guests to become Group Owner
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAST08' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Classification and M365 Groups - Allow Guests to become Group Owner' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Settings'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'AllowGuestsToBeGroupOwner' }).value

        if ($SettingValue -eq 'false') {
            $Status = 'Passed'
            $Result = 'Guests are not allowed to become group owners'
        } else {
            $Status = 'Failed'
            $Result = @"
Guests should not be allowed to become group owners to maintain proper access control.

**Current Configuration:**
- AllowGuestsToBeGroupOwner: $SettingValue

**Recommended Configuration:**
- AllowGuestsToBeGroupOwner: false
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAST08' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Classification and M365 Groups - Allow Guests to become Group Owner' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Settings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAST08' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Classification and M365 Groups - Allow Guests to become Group Owner' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Settings'
    }
}
