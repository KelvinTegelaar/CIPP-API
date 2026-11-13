function Invoke-CippTestZTNA35029 {
    <#
    .SYNOPSIS
    Mail flow rules apply rights protection to sensitive messages
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35029'; TestType = 'Identity'; Name = 'Mail flow rules apply rights protection to sensitive messages'; Risk = 'Medium'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Information Protection' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35029' -TenantFilter $Tenant -RequiredCapabilities @('RMS_S_PREMIUM2') -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection P2. Required capability: RMS_S_PREMIUM2.'
            return
        }

        $Rules = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoTransportRules'
        if (-not $Rules -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'ExoTransportRules' -CountsOnly)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $ProtectionRules = @($Rules.Where({ $_.ApplyOME -eq $true -or $_.ApplyRightsProtectionTemplate -or $_.ApplyClassification }))
        $EnabledCount = $ProtectionRules.Where({ $_.State -eq 'Enabled' }).Count

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($EnabledCount -ge 1) {
            $Status = 'Passed'
            $Lines.Add("✅ Mail flow rules with rights protection are configured, automatically protecting sensitive emails through encryption and restriction policies.`n")
        } else {
            $Status = 'Failed'
            $Lines.Add("❌ No mail flow rules with rights protection are configured; sensitive emails are not automatically protected in transit.`n")
        }

        if ($ProtectionRules.Count -gt 0) {
            $Lines.Add("### [Protection rules configuration](https://admin.exchange.microsoft.com/#/transportrules)`n")
            $Lines.Add('| Rule name | State | Priority | OME | RMS template | Classification | Last modified |')
            $Lines.Add('| :--- | :--- | :--- | :--- | :--- | :--- | :--- |')
            foreach ($Rule in [System.Linq.Enumerable]::OrderBy([object[]]$ProtectionRules, [Func[object, int]] { param($R) [int]$R.Priority })) {
                $StateIcon = if ($Rule.State -eq 'Enabled') { '✅' } else { '❌' }
                $Ome = if ($Rule.ApplyOME -eq $true) { 'Yes' } else { 'No' }
                $Rms = if ($Rule.ApplyRightsProtectionTemplate) { $Rule.ApplyRightsProtectionTemplate } else { 'N/A' }
                $Classification = if ($Rule.ApplyClassification) { $Rule.ApplyClassification } else { 'N/A' }
                $Modified = if ($Rule.WhenChanged) { ([datetime]$Rule.WhenChanged).ToString('yyyy-MM-dd') } else { 'N/A' }
                $Lines.Add("| [$($Rule.Name)](https://admin.exchange.microsoft.com/#/transportrules) | $StateIcon $($Rule.State) | $($Rule.Priority) | $Ome | $Rms | $Classification | $Modified |")
            }
            $Lines.Add('')
        }

        $ExternalProtection = if ($ProtectionRules.Where({ $_.SentToScope -eq 'NotInOrganization' }).Count -gt 0) { '✅ Yes' } else { '❌ No' }
        $Lines.Add("### Rules by action type`n")
        $Lines.Add('| Action type | Count |')
        $Lines.Add('| :--- | :--- |')
        $Lines.Add("| OME encryption rules | $($ProtectionRules.Where({ $_.ApplyOME -eq $true }).Count) |")
        $Lines.Add("| RMS template application | $($ProtectionRules.Where({ $_.ApplyRightsProtectionTemplate }).Count) |")
        $Lines.Add("| Classification rules | $($ProtectionRules.Where({ $_.ApplyClassification }).Count) |")
        $Lines.Add("`n### Summary`n")
        $Lines.Add('| Metric | Count |')
        $Lines.Add('| :--- | :--- |')
        $Lines.Add("| Total protection rules | $($ProtectionRules.Count) |")
        $Lines.Add("| Enabled rules | $EnabledCount |")
        $Lines.Add("| Disabled rules | $($ProtectionRules.Count - $EnabledCount) |")
        $Lines.Add("| External email protection | $ExternalProtection |")

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown ($Lines -join "`n")
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
