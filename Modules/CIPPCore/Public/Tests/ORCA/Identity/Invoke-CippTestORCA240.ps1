function Invoke-CippTestORCA240 {
    <#
    .SYNOPSIS
    Outlook external tags are configured
    #>
    param($Tenant)

    try {
        $OrgConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $OrgConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA240' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Outlook external tags are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Configuration'
            return
        }

        $Config = $OrgConfig | Select-Object -First 1

        if ($Config.ExternalInOutlook -ne 'Disabled') {
            $Status = 'Passed'
            $Result = "Outlook external tags are configured.`n`n"
            $Result += "**ExternalInOutlook:** $($Config.ExternalInOutlook)"
        } else {
            $Status = 'Failed'
            $Result = "Outlook external tags are NOT configured.`n`n"
            $Result += "**ExternalInOutlook:** $($Config.ExternalInOutlook)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA240' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Outlook external tags are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Configuration'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA240' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Outlook external tags are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Configuration'
    }
}
