function Invoke-CippTestZTNA21984 {
    <#
    .SYNOPSIS
    No Active low priority Entra recommendations found
    #>
    param($Tenant)

    try {
        $Recommendations = Get-CIPPTestData -TenantFilter $Tenant -Type 'DirectoryRecommendations'

        if (-not $Recommendations) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21984' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'No Active low priority Entra recommendations found' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
            return
        }

        $Active = $Recommendations.Where({ $_.status -eq 'active' -and $_.priority -eq 'low' })

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($Active.Count -eq 0) {
            $Status = 'Passed'
            $Lines.Add('No active low-priority Microsoft Entra recommendations were found.')
        } else {
            $Status = 'Failed'
            $Lines.Add("$($Active.Count) active low-priority Microsoft Entra recommendation(s) found.")
            $Lines.Add('')
            $Lines.Add('| Recommendation | Impact | Last Action |')
            $Lines.Add('| :------------- | :----- | :---------- |')
            foreach ($R in ($Active | Select-Object -First 25)) {
                $Lines.Add("| $($R.displayName) | $($R.impactType ?? '-') | $($R.lastModifiedDateTime ?? '-') |")
            }
            if ($Active.Count -gt 25) {
                $Lines.Add('')
                $Lines.Add("...and $($Active.Count - 25) more.")
            }
            $Lines.Add('')
            $Lines.Add('**Remediation:** Review the recommendations in the Microsoft Entra admin center under Identity > Overview > Recommendations and apply or postpone each item.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21984' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'Low' -Name 'No Active low priority Entra recommendations found' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21984' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'No Active low priority Entra recommendations found' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access Control'
    }
}
