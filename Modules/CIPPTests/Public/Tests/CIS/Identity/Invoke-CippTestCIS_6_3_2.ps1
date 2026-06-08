function Invoke-CippTestCIS_6_3_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (6.3.2) - Ensure the ability to add personal email accounts and calendars is disabled
    #>
    param($Tenant)

    try {
        $Owa = Get-CIPPTestData -TenantFilter $Tenant -Type 'OwaMailboxPolicy'

        if (-not $Owa) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_3_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'OwaMailboxPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Adding personal email accounts and calendars is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Default = $Owa | Where-Object { $_.Identity -eq 'OwaMailboxPolicy-Default' -or $_.IsDefault -eq $true } | Select-Object -First 1
        if (-not $Default) { $Default = $Owa | Select-Object -First 1 }

        if ($Default.PersonalAccountsEnabled -eq $false -and $Default.PersonalAccountCalendarsEnabled -eq $false) {
            $Status = 'Passed'
            $Result = "Adding personal email accounts and calendars is disabled on '$($Default.Identity)'."
        } else {
            $Status = 'Failed'
            $Result = "Adding personal email accounts and/or calendars is not fully disabled on '$($Default.Identity)' (PersonalAccountsEnabled: $($Default.PersonalAccountsEnabled), PersonalAccountCalendarsEnabled: $($Default.PersonalAccountCalendarsEnabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_3_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Adding personal email accounts and calendars is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_6_3_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Adding personal email accounts and calendars is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
