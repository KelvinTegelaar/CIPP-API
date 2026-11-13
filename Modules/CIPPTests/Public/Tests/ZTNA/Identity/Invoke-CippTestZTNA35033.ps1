function Invoke-CippTestZTNA35033 {
    <#
    .SYNOPSIS
    Custom sensitive information types are configured
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35033'; TestType = 'Identity'; Name = 'Custom sensitive information types are configured'; Risk = 'High'; UserImpact = 'Medium'; ImplementationEffort = 'High'; Category = 'Advanced Classification' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35033' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_ENTERPRISE') -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Exchange Online Plan 2. Required capability: EXCHANGE_S_ENTERPRISE.'
            return
        }
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35033' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'Sensitive information types are only collected for tenants licensed for Microsoft Purview Information Protection (RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2).'
            return
        }

        # The cache holds the non-Microsoft rule packages; each Entity/Affinity in a package is one custom SIT.
        $RulePackages = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoDlpSensitiveInfoTypes').Where({ $_ })
        if ($RulePackages.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoDlpSensitiveInfoTypes' -CountsOnly)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $CustomSits = foreach ($Package in $RulePackages) {
            if (-not $Package.ClassificationRuleCollectionXml) { continue }
            $Rules = ([xml]$Package.ClassificationRuleCollectionXml).RulePackage.Rules
            $Resources = @{}
            foreach ($Resource in $Rules.LocalizedStrings.Resource) { $Resources[$Resource.idRef] = $Resource }
            foreach ($Sit in @($Rules.Entity) + @($Rules.Affinity)) {
                if (-not $Sit) { continue }
                $Resource = $Resources[$Sit.id]
                [pscustomobject]@{
                    Name        = @($Resource.Name)[0].'#text'
                    Description = @($Resource.Description)[0].'#text'
                    Publisher   = $Package.Publisher
                }
            }
        }
        $CustomSits = @($CustomSits)

        if ($CustomSits.Count -eq 0) {
            Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown '❌ No custom Sensitive Information Types are configured; relying solely on built-in SIT patterns.'
            return
        }

        $Rows = foreach ($Sit in $CustomSits) {
            $Description = if ($Sit.Description) { $Sit.Description } else { 'Not specified' }
            $Publisher = if ($Sit.Publisher) { $Sit.Publisher } else { 'Not specified' }
            "| $($Sit.Name) | $Description | $Publisher |"
        }
        $Result = @"
✅ Custom Sensitive Information Types are configured, enabling detection of organization-specific sensitive data patterns.

## [Custom Sensitive Information Types](https://purview.microsoft.com/informationprotection/dataclassification/sensinfoTypes)

| Name | Description | Publisher |
| :--- | :--- | :--- |
$($Rows -join "`n")

**Summary:**
* Total Custom SITs: $($CustomSits.Count)
"@

        Add-CippTestResult @TestParams -Status 'Passed' -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
