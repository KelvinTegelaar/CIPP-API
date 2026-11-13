function Invoke-CippTestZTNA35027 {
    <#
    .SYNOPSIS
    Custom branding templates are configured for Microsoft Purview Message Encryption
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35027'; TestType = 'Identity'; Name = 'Custom branding templates are configured for Microsoft Purview Message Encryption'; Risk = 'Low'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'Information Protection' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35027' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection. Required capabilities: RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2.'
            return
        }

        $Configs = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOMEConfiguration').Where({ $_ })
        if ($Configs.Count -eq 0) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $BrandingFields = 'EmailText', 'ImageUrl', 'BackgroundColor', 'PortalText', 'IntroductionText', 'DisclaimerText'
        $BrandedCount = 0
        $Rows = foreach ($Config in $Configs) {
            $Cells = foreach ($Field in $BrandingFields) {
                $Value = $Config.$Field
                if ([string]::IsNullOrWhiteSpace($Value)) {
                    if ($Field -eq 'ImageUrl') { '❌ No' } else { '❌ None' }
                } elseif ($Field -eq 'ImageUrl') { '✅ Yes' } else { "✅ $Value" }
            }
            if ($Cells -match '✅') { $BrandedCount++ }
            "| $($Config.Identity) | $($Cells -join ' | ') |"
        }

        $Status, $Headline = if ($BrandedCount -gt 0) {
            'Passed', '✅ Custom OME branding has been configured, providing a branded encryption portal experience for external recipients.'
        } else {
            'Failed', '❌ OME custom branding is not configured; the encryption portal uses generic Microsoft branding.'
        }
        $Result = @"
$Headline

**Summary:**

- Total OME Configurations: $($Configs.Count)
- Configured with Custom Branding: $BrandedCount

**Configuration Details:**

| Configuration identity | Email text | Logo configured | Background color | Portal text | Introduction text | Disclaimer text |
|:-----------------------|:-----------|:----------------|:-----------------|:------------|:------------------|:----------------|
$($Rows -join "`n")
"@

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
