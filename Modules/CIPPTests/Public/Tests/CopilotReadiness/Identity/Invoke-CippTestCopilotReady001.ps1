function Invoke-CippTestCopilotReady001 {
    <#
    .SYNOPSIS
    Tenant has at least one Microsoft 365 Copilot prerequisite license
    #>
    param($Tenant)

    # Service plan names that indicate a qualifying Copilot base license.
    # All Microsoft 365 Copilot-eligible plans (E3, E5, Business Basic/Standard/Premium, F1, F3, A1/A3/A5)
    # include Teams (TEAMS1 or MCOSTANDARD). Using service plans avoids dependency on SKU part number
    # values — CIPP's LicenseOverview caches friendly display names, not raw API SKU codes.
    # https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-licensing
    $PrerequisiteServicePlans = @('TEAMS1', 'MCOSTANDARD')

    try {
        $LicenseData = Get-CIPPTestData -TenantFilter $Tenant -Type 'LicenseOverview'

        if (-not $LicenseData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady001' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No license data found in database. Data collection may not yet have run for this tenant.' -Risk 'High' -Name 'Tenant has M365 Copilot prerequisite licenses' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Copilot Readiness'
            return
        }

        # LicenseOverview is stored as a single item; unwrap if needed
        $Skus = if ($LicenseData.Licenses) { $LicenseData.Licenses } else { $LicenseData }

        $EligibleSkus = [System.Collections.Generic.List[object]]::new()
        $AssignableCount = 0

        foreach ($Sku in $Skus) {
            $HasQualifyingPlan = $Sku.ServicePlans | Where-Object { $_.servicePlanName -in $PrerequisiteServicePlans }
            if ($HasQualifyingPlan -and [int]$Sku.TotalLicenses -gt 0) {
                $EligibleSkus.Add($Sku) | Out-Null
                $AssignableCount += [int]$Sku.TotalLicenses
            }
        }

        if ($EligibleSkus.Count -gt 0) {
            $Status = 'Passed'
            $Result = "Tenant has **$($EligibleSkus.Count)** eligible prerequisite license plan(s) covering **$AssignableCount** seats that qualify for Microsoft 365 Copilot.`n`n"
            $Result += "| License | Total Seats | Assigned |`n"
            $Result += "|---------|------------|---------|`n"
            foreach ($Sku in $EligibleSkus) {
                $Result += "| $($Sku.License) | $($Sku.TotalLicenses) | $($Sku.CountUsed) |`n"
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
