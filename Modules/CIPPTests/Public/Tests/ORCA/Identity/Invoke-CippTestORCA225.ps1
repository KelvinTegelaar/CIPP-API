function Invoke-CippTestORCA225 {
    <#
    .SYNOPSIS
    Safe Documents is enabled for Office clients
    #>
    param($Tenant)

    try {
        $AtpPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAtpPolicyForO365'

        if (-not $AtpPolicy) {
            if (-not (Test-CIPPStandardLicense -StandardName 'ORCA225' -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA225' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365 (ATP). Required capabilities: ATP_ENTERPRISE, ATP_ENTERPRISE_GOV, THREAT_INTELLIGENCE, THREAT_INTELLIGENCE_GOV.' -Risk 'Medium' -Name 'Safe Documents is enabled for Office clients' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA225' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in the database. Data collection for this tenant may not have completed yet - refresh the cache and try again.' -Risk 'Medium' -Name 'Safe Documents is enabled for Office clients' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            }
            return
        }

        $Policy = $AtpPolicy | Select-Object -First 1

        if ($Policy.EnableSafeDocs -eq $true) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("Safe Documents is enabled for Office clients.`n`n")
            $null = $Result.Append("**EnableSafeDocs:** $($Policy.EnableSafeDocs)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("Safe Documents is NOT enabled for Office clients.`n`n")
            $null = $Result.Append("**EnableSafeDocs:** $($Policy.EnableSafeDocs)")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA225' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Safe Documents is enabled for Office clients' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA225' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Safe Documents is enabled for Office clients' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'
    }
}
