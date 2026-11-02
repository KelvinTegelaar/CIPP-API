function Invoke-CippTestORCA236 {
    <#
    .SYNOPSIS
    Safe Links is enabled for emails
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoSafeLinksPolicies'

        if (-not $Policies) {
            if (-not (Test-CIPPStandardLicense -StandardName 'ORCA236' -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA236' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365 (ATP). Required capabilities: ATP_ENTERPRISE, ATP_ENTERPRISE_GOV, THREAT_INTELLIGENCE, THREAT_INTELLIGENCE_GOV.' -Risk 'High' -Name 'Safe Links is enabled for emails' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
            } else {
                Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA236' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in the database. Data collection for this tenant may not have completed yet - refresh the cache and try again.' -Risk 'High' -Name 'Safe Links is enabled for emails' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
            }
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()
        $PassedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $Policies) {
            if ($Policy.EnableSafeLinksForEmail -eq $true) {
                $PassedPolicies.Add($Policy) | Out-Null
            } else {
                $FailedPolicies.Add($Policy) | Out-Null
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Status = 'Passed'
            $Result = [System.Text.StringBuilder]::new("All Safe Links policies have email protection enabled.`n`n")
            $null = $Result.Append("**Compliant Policies:** $($PassedPolicies.Count)")
        } else {
            $Status = 'Failed'
            $Result = [System.Text.StringBuilder]::new("$($FailedPolicies.Count) Safe Links policies do not have email protection enabled.`n`n")
            $null = $Result.Append("**Non-Compliant Policies:** $($FailedPolicies.Count)`n`n")
            $null = $Result.Append("| Policy Name | Enable Safe Links For Email |`n")
            $null = $Result.Append("|------------|----------------------------|`n")
            foreach ($Policy in $FailedPolicies) {
                $null = $Result.Append("| $($Policy.Identity) | $($Policy.EnableSafeLinksForEmail) |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA236' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe Links is enabled for emails' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA236' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe Links is enabled for emails' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Links'
    }
}
