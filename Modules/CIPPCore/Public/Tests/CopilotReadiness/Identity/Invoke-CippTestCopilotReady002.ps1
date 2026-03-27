function Invoke-CippTestCopilotReady002 {
    <#
    .SYNOPSIS
    Microsoft 365 Copilot licenses are assigned and available seats remain
    #>
    param($Tenant)

    # All known Copilot add-on SKU part numbers
    $CopilotSkus = @(
        'Microsoft_365_Copilot',       # Microsoft Copilot for Microsoft 365 (commercial)
        'Microsoft_365_Copilot_EDU',   # Microsoft 365 Copilot (Education Faculty)
        'Microsoft_365_Copilot_GCC'    # Microsoft 365 Copilot (GCC)
    )

    try {
        $LicenseData = New-CIPPDbRequest -TenantFilter $Tenant -Type 'LicenseOverview'

        if (-not $LicenseData) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady002' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No license data found in database. Data collection may not yet have run for this tenant.' -Risk 'High' -Name 'Microsoft 365 Copilot licenses assigned' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
            return
        }

        $Skus = if ($LicenseData.Licenses) { $LicenseData.Licenses } else { $LicenseData }

        $CopilotLicenses = [System.Collections.Generic.List[object]]::new()
        $TotalEnabled = 0
        $TotalConsumed = 0
        $TotalAvailable = 0

        foreach ($Sku in $Skus) {
            if ($Sku.skuPartNumber -in $CopilotSkus) {
                $CopilotLicenses.Add($Sku) | Out-Null
                $TotalEnabled += $Sku.prepaidUnits.enabled
                $TotalConsumed += $Sku.consumedUnits
                $TotalAvailable += ($Sku.prepaidUnits.enabled - $Sku.consumedUnits)
            }
        }

        if ($CopilotLicenses.Count -eq 0) {
            $Status = 'Failed'
            $Result = "No Microsoft 365 Copilot add-on licenses were found in this tenant.`n`n"
            $Result += "Purchase Microsoft 365 Copilot licenses and assign them to eligible users to enable Copilot features."
        } elseif ($TotalConsumed -eq 0) {
            $Status = 'Failed'
            $Result = "Microsoft 365 Copilot licenses exist (**$TotalEnabled** seats) but **none are assigned** to any users.`n`n"
            $Result += "| SKU | Enabled | Assigned | Available |`n"
            $Result += "|-----|---------|----------|-----------|`n"
            foreach ($Sku in $CopilotLicenses) {
                $Available = $Sku.prepaidUnits.enabled - $Sku.consumedUnits
                $Result += "| $($Sku.skuPartNumber) | $($Sku.prepaidUnits.enabled) | $($Sku.consumedUnits) | $Available |`n"
            }
        } else {
            $Status = 'Passed'
            $Result = "Microsoft 365 Copilot licenses are purchased and assigned.`n`n"
            $Result += "| SKU | Enabled | Assigned | Available |`n"
            $Result += "|-----|---------|----------|-----------|`n"
            foreach ($Sku in $CopilotLicenses) {
                $Available = $Sku.prepaidUnits.enabled - $Sku.consumedUnits
                $Result += "| $($Sku.skuPartNumber) | $($Sku.prepaidUnits.enabled) | $($Sku.consumedUnits) | $Available |`n"
            }
            if ($TotalAvailable -gt 0) {
                $Result += "`n**$TotalAvailable unassigned seat(s)** are available to assign to additional users."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady002' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Microsoft 365 Copilot licenses assigned' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Copilot Readiness'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CopilotReady002: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CopilotReady002' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Microsoft 365 Copilot licenses assigned' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Copilot Readiness'
    }
}
