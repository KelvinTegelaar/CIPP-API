function Invoke-CippTestZTNA35005 {
    <#
    .SYNOPSIS
    Sensitivity labels are enabled for SharePoint and OneDrive
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35005'; TestType = 'Identity'; Name = 'Sensitivity labels are enabled for SharePoint and OneDrive'; Risk = 'High'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'SharePoint Online' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35005' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection. Required capabilities: RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2.'
            return
        }

        $SPOTenant = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant')[0]
        if (-not $SPOTenant) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $Enabled = $SPOTenant.EnableAIPIntegration -eq $true
        $Status, $Headline = if ($Enabled) {
            'Passed', '✅ Sensitivity labels are enabled in SharePoint Online and OneDrive, allowing users to classify and protect documents stored in these services.'
        } else {
            'Failed', '❌ Sensitivity labels are NOT enabled in SharePoint Online and OneDrive. Documents cannot be labeled or protected with encryption/access controls.'
        }
        $Result = "$Headline`n`n### SharePoint Online Configuration Summary`n`n**Tenant Settings:**`n* EnableAIPIntegration: $Enabled`n`n[Manage Information protection in SharePoint Admin Center](https://admin.microsoft.com/sharepoint?page=classicSettings&modern=true)"

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
