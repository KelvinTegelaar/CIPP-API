function Invoke-CippTestCIS_3_2_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (3.2.2) - DLP policies SHALL be enabled for Microsoft Teams
    #>
    param($Tenant)

    try {
        $Dlp = Get-CIPPTestData -TenantFilter $Tenant -Type 'DlpCompliancePolicies'

        if (-not $Dlp) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DlpCompliancePolicies cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'DLP policies are enabled for Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
            return
        }

        $TeamsDlp = $Dlp | Where-Object {
            $_.Mode -eq 'Enable' -and $_.Enabled -eq $true -and (
                $_.TeamsLocation -or
                $_.Workload -match 'Teams' -or
                $_.TeamsLocationException -ne $null
            )
        }

        if ($TeamsDlp.Count -gt 0) {
            $Status = 'Passed'
            $Result = "$($TeamsDlp.Count) DLP policy/policies cover Microsoft Teams:`n`n"
            $Result += ($TeamsDlp | ForEach-Object { "- $($_.Name)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled DLP policy currently covers Microsoft Teams. Add Teams to the locations of at least one enforced DLP policy.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'DLP policies are enabled for Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'DLP policies are enabled for Microsoft Teams' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
    }
}
