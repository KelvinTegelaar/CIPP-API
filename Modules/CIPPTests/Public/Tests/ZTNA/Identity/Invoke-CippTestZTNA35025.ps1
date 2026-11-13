function Invoke-CippTestZTNA35025 {
    <#
    .SYNOPSIS
    Internal Rights Management licensing is enabled
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35025'; TestType = 'Identity'; Name = 'Internal Rights Management licensing is enabled'; Risk = 'High'; UserImpact = 'High'; ImplementationEffort = 'Low'; Category = 'Rights Management Service (RMS)' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35025' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection. Required capabilities: RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2.'
            return
        }

        $IrmConfig = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoIRMConfiguration')[0]
        if (-not $IrmConfig) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        if ($null -eq $IrmConfig.InternalLicensingEnabled) {
            Add-CippTestResult @TestParams -Status 'Investigate' -ResultMarkdown "### Investigate`n`nUnable to determine internal RMS licensing status due to permissions issues or incomplete configuration data."
            return
        }

        $Status, $Headline, $Config = if ($IrmConfig.InternalLicensingEnabled -eq $true) {
            'Passed', '✅ Internal RMS licensing is enabled, allowing internal users to license and share protected content within the organization.', '✅ Enabled'
        } else {
            'Failed', '❌ Internal RMS licensing is not enabled or licensing endpoints are not configured.', '❌ Disabled'
        }
        $External = if ($null -eq $IrmConfig.ExternalLicensingEnabled) { 'Unknown' } else { $IrmConfig.ExternalLicensingEnabled }
        $AzureRms = if ($null -eq $IrmConfig.AzureRMSLicensingEnabled) { 'Unknown' } else { $IrmConfig.AzureRMSLicensingEnabled }
        $Location, $Endpoints = if ($IrmConfig.LicensingLocation) { (@($IrmConfig.LicensingLocation) -join ', '), '✅ Configured' } else { 'Not configured', '❌ Not Configured' }
        $Result = @"
$Headline

**[Internal RMS Licensing Status](https://purview.microsoft.com/settings/encryption)**
| Setting | Status |
| :--- | :--- |
| InternalLicensingEnabled | $($IrmConfig.InternalLicensingEnabled) |
| ExternalLicensingEnabled | $External |
| AzureRMSLicensingEnabled | $AzureRms |
| LicensingLocation | $Location |

**Summary:**
* Internal Licensing Configuration: $Config
* Licensing Endpoints: $Endpoints
"@

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
