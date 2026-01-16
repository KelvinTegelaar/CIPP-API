function Invoke-CippTestORCA158 {
    <#
    .SYNOPSIS
    Safe Attachments is enabled for SharePoint and Teams
    #>
    param($Tenant)

    try {
        $AtpPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAtpPolicyForO365'

        if (-not $AtpPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA158' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Safe Attachments enabled for SharePoint and Teams' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            return
        }

        $Policy = $AtpPolicy | Select-Object -First 1

        if ($Policy.EnableATPForSPOTeamsODB -eq $true) {
            $Status = 'Passed'
            $Result = "Safe Attachments is enabled for SharePoint, OneDrive, and Teams.`n`n"
            $Result += "**EnableATPForSPOTeamsODB:** $($Policy.EnableATPForSPOTeamsODB)"
        } else {
            $Status = 'Failed'
            $Result = "Safe Attachments is NOT enabled for SharePoint, OneDrive, and Teams.`n`n"
            $Result += "**EnableATPForSPOTeamsODB:** $($Policy.EnableATPForSPOTeamsODB)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA158' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe Attachments enabled for SharePoint and Teams' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA158' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe Attachments enabled for SharePoint and Teams' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'
    }
}
