function Invoke-CippTestORCA189 {
    <#
    .SYNOPSIS
    Safe Attachments is not bypassed
    #>
    param($Tenant)
    
    try {
        $Rules = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoTransportRules'
        
        if (-not $Rules) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA189' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Safe Attachments is not bypassed' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            return
        }

        $BypassRules = [System.Collections.Generic.List[object]]::new()
        foreach ($Rule in $Rules) {
            if ($Rule.SetHeaderName -eq 'X-MS-Exchange-Organization-SkipSafeAttachmentProcessing' -and $Rule.SetHeaderValue -eq '1') {
                $BypassRules.Add($Rule) | Out-Null
            }
        }

        if ($BypassRules.Count -eq 0) {
            $Status = 'Passed'
            $Result = "No transport rules are bypassing Safe Attachments processing."
        } else {
            $Status = 'Failed'
            $Result = "$($BypassRules.Count) transport rules are bypassing Safe Attachments processing.`n`n"
            $Result += "| Rule Name | Priority |`n"
            $Result += "|-----------|----------|`n"
            foreach ($Rule in $BypassRules) {
                $Result += "| $($Rule.Name) | $($Rule.Priority) |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA189' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Safe Attachments is not bypassed' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA189' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Safe Attachments is not bypassed' -UserImpact 'High' -ImplementationEffort 'Low' -Category 'Safe Attachments'
    }
}
