function Invoke-CippTestZTNA35004 {
    <#
    .SYNOPSIS
    Sensitivity label policies are published to users
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35004'; TestType = 'Identity'; Name = 'Sensitivity label policies are published to users'; Risk = 'Low'; UserImpact = 'Medium'; ImplementationEffort = 'Low'; Category = 'Sensitivity Labels' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35004' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection. Required capabilities: RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2.'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoLabelPolicies').Where({ $_ })
        if ($Policies.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoLabelPolicies' -CountsOnly)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $EnabledCount = $Policies.Where({ $_.Enabled -eq $true }).Count
        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($EnabledCount -ge 1) {
            $Status = 'Passed'
            $Lines.Add("✅ At least one enabled label policy is published to users.`n")
        } else {
            $Status = 'Failed'
            $Lines.Add("❌ No enabled label policies exist or all policies are disabled.`n")
        }
        $Lines.Add("### Label Policy Summary`n")
        $Lines.Add("* Total Policies Configured: $($Policies.Count)")
        $Lines.Add("* Enabled Policies: $EnabledCount")
        $Lines.Add("* Disabled Policies: $($Policies.Count - $EnabledCount)")
        if ($Policies.Count -gt 0) {
            $Lines.Add("`n**Policies:**")
            $Lines.Add('| Policy name | Enabled | Labels included |')
            $Lines.Add('|:---|:---|:---|')
            foreach ($Policy in $Policies) {
                $Lines.Add("| $($Policy.Name) | $($Policy.Enabled -eq $true) | $(@($Policy.Labels).Where({ $_ }).Count) |")
            }
        }
        $Lines.Add("`n[Manage Label Policies in Microsoft Purview](https://purview.microsoft.com/informationprotection/labelpolicies)")

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown ($Lines -join "`n")
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
