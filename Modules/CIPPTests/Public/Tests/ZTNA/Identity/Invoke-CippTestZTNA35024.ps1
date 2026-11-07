function Invoke-CippTestZTNA35024 {
    <#
    .SYNOPSIS
    Azure Rights Management service is activated
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35024'; TestType = 'Identity'; Name = 'Azure Rights Management service is activated'; Risk = 'High'; UserImpact = 'High'; ImplementationEffort = 'Low'; Category = 'Rights Management Service' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35024' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection. Required capabilities: RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2.'
            return
        }

        $IrmConfig = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoIRMConfiguration')[0]
        if (-not $IrmConfig) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $Status, $Headline, $Summary = if ($IrmConfig.AzureRMSLicensingEnabled -eq $true) {
            'Passed', '✅ Azure RMS is enabled at the tenant level, enabling all downstream encryption and rights management capabilities.', '✅ Enabled'
        } else {
            'Failed', '❌ Azure RMS is not enabled or is disabled for the tenant.', '❌ Disabled'
        }
        $Created = if ($IrmConfig.WhenCreatedUTC) { $IrmConfig.WhenCreatedUTC } else { 'N/A' }
        $Result = @"
$Headline

### Azure RMS Status

| Setting | Value |
| :------ | :---- |
| AzureRMSLicensingEnabled | $($IrmConfig.AzureRMSLicensingEnabled) |
| SimplifiedClientAccessEnabled | $($IrmConfig.SimplifiedClientAccessEnabled) |
| InternalLicensingEnabled | $($IrmConfig.InternalLicensingEnabled) |
| ExternalLicensingEnabled | $($IrmConfig.ExternalLicensingEnabled) |
| Configuration Created | $Created |

**Summary:**

 Azure RMS Service: $Summary
"@

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
