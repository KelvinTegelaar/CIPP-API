function Invoke-CippTestCopilotReady001 {
    <#
    .SYNOPSIS
    Tenant has at least one Microsoft 365 Copilot prerequisite license
    #>
    param($Tenant)

    # SKU part numbers that qualify as Copilot prerequisites per Microsoft licensing docs
    # https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-licensing
    $PrerequisiteSkus = @(
        'SPE_E3', 'SPE_E5',                                         # Microsoft 365 E3/E5
        'M365_F1', 'M365_F3',                                       # Microsoft 365 F1/F3
        'O365_BUSINESS_ESSENTIALS', 'O365_BUSINESS_PREMIUM',        # M365 Business Basic/Standard
        'SPB',                                                       # M365 Business Premium
        'MCOEV', 'ENTERPRISEPACK', 'ENTERPRISEPREMIUM',             # Office 365 E1/E3/E5
        'DESKLESSPACK',                                              # Office 365 F3
        'MCOSTANDARD', 'MCOSTANDARD_GOV',                           # Teams Essentials / Enterprise
        'EXCHANGESTANDARD', 'EXCHANGEENTERPRISE',                   # Exchange Plan 1/2
        'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE',               # SharePoint Plan 1/2
        'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE',                    # OneDrive Plan 1/2
        'PROJECTESSENTIALS', 'PROJECTPREMIUM', 'PROJECTPROFESSIONAL', # Project plans
        'VISIOONLINE_PLAN1', 'VISIOCLIENT',                         # Visio plans
        'M365EDU_A1', 'M365EDU_A3_FACULTY', 'M365EDU_A5_FACULTY',  # Education
        'STANDARDPACK', 'STANDARDWOFFPACK_FACULTY'                  # Office 365 A1/A3
    )

    try {
        $LicenseData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'LicenseOverview'

        if (-not $LicenseData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady001' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No license data found in database. Data collection may not yet have run for this tenant.' -Risk 'High' -Name 'Tenant has M365 Copilot prerequisite licenses' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        # LicenseOverview is stored as a single item; unwrap if needed
        $Skus = if ($LicenseData.Licenses) { $LicenseData.Licenses } else { $LicenseData }

        $EligibleSkus = [System.Collections.Generic.List[object]]::new()
        $AssignableCount = 0

        foreach ($Sku in $Skus) {
            if ($Sku.skuPartNumber -in $PrerequisiteSkus -and $Sku.prepaidUnits.enabled -gt 0) {
                $EligibleSkus.Add($Sku) | Out-Null
                $AssignableCount += $Sku.prepaidUnits.enabled
            }
        }

        if ($EligibleSkus.Count -gt 0) {
            $Status = 'Passed'
            $Result = "Tenant has **$($EligibleSkus.Count)** eligible prerequisite license plan(s) covering **$AssignableCount** seats that qualify for Microsoft 365 Copilot.`n`n"
            $Result += "| License | Enabled Seats | Consumed |`n"
            $Result += "|---------|--------------|---------|`n"
            foreach ($Sku in $EligibleSkus) {
                $Result += "| $($Sku.skuPartNumber) | $($Sku.prepaidUnits.enabled) | $($Sku.consumedUnits) |`n"
            }
        } else {
            $Status = 'Failed'
            $Result = "No Microsoft 365 Copilot prerequisite licenses were found in this tenant.`n`n"
            $Result += 'Users must have an eligible M365 plan before a Copilot add-on license can be assigned. '
            $Result += 'See [Microsoft licensing requirements](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-licensing) for the full list.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady001' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Tenant has M365 Copilot prerequisite licenses' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady001: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady001' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Tenant has M365 Copilot prerequisite licenses' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
    }
}
