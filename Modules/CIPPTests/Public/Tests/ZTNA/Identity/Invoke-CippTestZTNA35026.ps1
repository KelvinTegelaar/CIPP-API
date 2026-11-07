function Invoke-CippTestZTNA35026 {
    <#
    .SYNOPSIS
    Microsoft Purview Message Encryption is configured with simplified client access
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35026'; TestType = 'Identity'; Name = 'Microsoft Purview Message Encryption is configured with simplified client access'; Risk = 'Medium'; UserImpact = 'Medium'; ImplementationEffort = 'Low'; Category = 'Microsoft Purview Message Encryption' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35026' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection. Required capabilities: RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2.'
            return
        }

        $IrmConfig = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoIRMConfiguration')[0]
        if (-not $IrmConfig) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $Status, $Headline = if ($null -eq $IrmConfig.SimplifiedClientAccessEnabled -or $null -eq $IrmConfig.AzureRMSLicensingEnabled) {
            'Investigate', '⚠️ Unable to determine SimplifiedClientAccessEnabled status due to permissions issues or OME not configured.'
        } elseif ($IrmConfig.AzureRMSLicensingEnabled -eq $true -and $IrmConfig.SimplifiedClientAccessEnabled -eq $true) {
            'Passed', '✅ SimplifiedClientAccessEnabled is true (Protect button enabled) and AzureRMSLicensingEnabled is true (encryption foundation active).'
        } else {
            'Failed', '❌ SimplifiedClientAccessEnabled is false or AzureRMSLicensingEnabled is false (encryption foundation or Protect button disabled).'
        }
        $ProtectButton = if ($Status -eq 'Passed') { '✅ Enabled' } else { '❌ Disabled' }
        $Result = @"
$Headline

### OME SimplifiedClientAccess Status

| Setting | Value |
| :------ | :---- |
| SimplifiedClientAccessEnabled | $($IrmConfig.SimplifiedClientAccessEnabled) |
| AzureRMSLicensingEnabled | $($IrmConfig.AzureRMSLicensingEnabled) |
| InternalLicensingEnabled | $($IrmConfig.InternalLicensingEnabled) |

**Summary:**

* Protect Button Status: $ProtectButton
"@

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
