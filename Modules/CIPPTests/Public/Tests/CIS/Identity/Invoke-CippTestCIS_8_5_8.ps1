function Invoke-CippTestCIS_8_5_8 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (8.5.8) - External meeting chat SHALL be off
    #>
    param($Tenant)

    try {
        $MP = Get-CIPPTestData -TenantFilter $Tenant -Type 'CsTeamsMeetingPolicy'

        if (-not $MP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_8' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'CsTeamsMeetingPolicy cache not found.' -Risk 'Medium' -Name 'External meeting chat is off' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
            return
        }

        $Cfg = $MP | Select-Object -First 1

        if ($Cfg.AllowExternalNonTrustedMeetingChat -eq $false) {
            $Status = 'Passed'
            $Result = 'External non-trusted meeting chat is disabled.'
        } else {
            $Status = 'Failed'
            $Result = "External non-trusted meeting chat is enabled (AllowExternalNonTrustedMeetingChat: $($Cfg.AllowExternalNonTrustedMeetingChat))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_8' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'External meeting chat is off' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_8_5_8' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'External meeting chat is off' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Meetings'
    }
}
