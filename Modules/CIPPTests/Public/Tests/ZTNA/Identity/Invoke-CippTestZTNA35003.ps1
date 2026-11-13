function Invoke-CippTestZTNA35003 {
    <#
    .SYNOPSIS
    Sensitivity labels are configured
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35003'; TestType = 'Identity'; Name = 'Sensitivity labels are configured'; Risk = 'High'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'sensitivity-labels' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35003' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection. Required capabilities: RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2.'
            return
        }

        $Labels = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoLabels').Where({ $_ })
        if ($Labels.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoLabels' -CountsOnly)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($Labels.Count -gt 0) {
            $Status = 'Passed'
            $Lines.Add("✅ At least one sensitivity label is configured in the tenant.`n")
        } else {
            $Status = 'Failed'
            $Lines.Add("❌ No sensitivity labels are configured.`n")
        }
        $Lines.Add("### Sensitivity Label Configuration Summary`n")
        $Lines.Add("* Total Label Count: $($Labels.Count)`n")
        if ($Labels.Count -gt 0) {
            $Lines.Add('**Sample Labels** (up to 5):')
            $Lines.Add('| Label Name |')
            $Lines.Add('|:---|')
            foreach ($Label in $Labels.Where({ $true }, 'First', 5)) {
                $Lines.Add("| $($Label.DisplayName) |")
            }
        }
        $Lines.Add("`n[Manage Sensitivity Labels in Microsoft Purview](https://purview.microsoft.com/informationprotection/informationprotectionlabels/sensitivitylabels)")

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown ($Lines -join "`n")
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
