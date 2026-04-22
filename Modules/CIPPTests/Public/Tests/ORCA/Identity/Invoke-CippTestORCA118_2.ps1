function Invoke-CippTestORCA118_2 {
    <#
    .SYNOPSIS
    Domains not allow listed in Transport Rules
    #>
    param($Tenant)

    try {
        $TransportRules = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoTransportRules'

        if (-not $TransportRules) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Domains not allow listed in Transport Rules' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Transport Rules'
            return
        }

        $FailedRules = [System.Collections.Generic.List[object]]::new()

        foreach ($Rule in $TransportRules) {
            # Check if rule sets SCL to -1 (bypass spam filtering) based on sender domain
            if ($Rule.SetSCL -eq -1 -and $Rule.SenderDomainIs) {
                $FailedRules.Add($Rule) | Out-Null
            }
        }

        if ($FailedRules.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No transport rules allow list domains by setting SCL to -1.`n`n"
            $Result += "**Total Transport Rules Checked:** $($TransportRules.Count)"
        } else {
            $Status = 'Failed'
            $Result = "$($FailedRules.Count) transport rules allow list domains by setting SCL to -1.`n`n"
            $Result += "**Non-Compliant Rules:** $($FailedRules.Count)`n`n"
            $Result += "| Rule Name | Sender Domains |`n"
            $Result += "|-----------|---------------|`n"
            foreach ($Rule in $FailedRules) {
                $Domains = if ($Rule.SenderDomainIs) { ($Rule.SenderDomainIs -join ', ') } else { 'N/A' }
                $Result += "| $($Rule.Name) | $Domains |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Domains not allow listed in Transport Rules' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Transport Rules'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA118_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Domains not allow listed in Transport Rules' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Transport Rules'
    }
}
