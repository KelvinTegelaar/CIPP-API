function Invoke-CippTestORCA158 {
    <#
    .SYNOPSIS
    Safe Attachments is enabled for SharePoint and Teams
    #>
    param($Tenant)

    try {
        $AtpPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAtpPolicyForO365'

        if (-not $AtpPolicy) {
            if (-not (Test-CIPPStandardLicense -StandardName 'ORCA158' -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA158' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365 (ATP). Required capabilities: ATP_ENTERPRISE, ATP_ENTERPRISE_GOV, THREAT_INTELLIGENCE, THREAT_INTELLIGENCE_GOV.' -Risk 'High' -Name 'Safe Attachments enabled for SharePoint and Teams' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA158' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in the database. Data collection for this tenant may not have completed yet - refresh the cache and try again.' -Risk 'High' -Name 'Safe Attachments enabled for SharePoint and Teams' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            }
            return
        }

        $Policy = $AtpPolicy | Select-Object -First 1

        if ($Policy.EnableATPForSPOTeamsODB -eq $true) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("Safe Attachments is enabled for SharePoint, OneDrive, and Teams.`n`n")
            $null = $Result.Append("**EnableATPForSPOTeamsODB:** $($Policy.EnableATPForSPOTeamsODB)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("Safe Attachments is NOT enabled for SharePoint, OneDrive, and Teams.`n`n")
            $null = $Result.Append("**EnableATPForSPOTeamsODB:** $($Policy.EnableATPForSPOTeamsODB)")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA158' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe Attachments enabled for SharePoint and Teams' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA158' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe Attachments enabled for SharePoint and Teams' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'
    }
}
