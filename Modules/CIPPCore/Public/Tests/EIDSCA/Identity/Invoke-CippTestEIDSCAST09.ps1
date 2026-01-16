function Invoke-CippTestEIDSCAST09 {
    <#
    .SYNOPSIS
    Classification and M365 Groups - Allow Guests to have access to groups content
    #>
    param($Tenant)

    try {
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAST09' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Classification and M365 Groups - Allow Guests to have access to groups content' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Settings'
            return
        }

        $SettingValue = ($Settings.values | Where-Object { $_.name -eq 'AllowGuestsToAccessGroups' }).value

        if ($SettingValue -eq 'True') {
            $Status = 'Passed'
            $Result = 'Guests are allowed to access groups content'
        } else {
            $Status = 'Failed'
            $Result = @"
Guests should be allowed to access groups content for proper collaboration.

**Current Configuration:**
- AllowGuestsToAccessGroups: $SettingValue

**Recommended Configuration:**
- AllowGuestsToAccessGroups: True
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAST09' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Classification and M365 Groups - Allow Guests to have access to groups content' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Settings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAST09' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Classification and M365 Groups - Allow Guests to have access to groups content' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Settings'
    }
}
