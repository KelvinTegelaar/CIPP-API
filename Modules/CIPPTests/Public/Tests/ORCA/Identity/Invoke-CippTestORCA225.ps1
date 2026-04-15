function Invoke-CippTestORCA225 {
    <#
    .SYNOPSIS
    Safe Documents is enabled for Office clients
    #>
    param($Tenant)

    try {
        $AtpPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAtpPolicyForO365'

        if (-not $AtpPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA225' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Safe Documents is enabled for Office clients' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            return
        }

        $Policy = $AtpPolicy | Select-Object -First 1

        if ($Policy.EnableSafeDocs -eq $true) {
            $Status = 'Passed'
            $Result = "Safe Documents is enabled for Office clients.`n`n"
            $Result += "**EnableSafeDocs:** $($Policy.EnableSafeDocs)"
        } else {
            $Status = 'Failed'
            $Result = "Safe Documents is NOT enabled for Office clients.`n`n"
            $Result += "**EnableSafeDocs:** $($Policy.EnableSafeDocs)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA225' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Safe Documents is enabled for Office clients' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA225' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Safe Documents is enabled for Office clients' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'
    }
}
