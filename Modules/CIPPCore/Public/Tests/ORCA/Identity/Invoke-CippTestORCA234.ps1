function Invoke-CippTestORCA234 {
    <#
    .SYNOPSIS
    Click through is disabled for Safe Documents
    #>
    param($Tenant)

    try {
        $AtpPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoAtpPolicyForO365'

        if (-not $AtpPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA234' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Click through is disabled for Safe Documents' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'
            return
        }

        $Policy = $AtpPolicy | Select-Object -First 1

        if ($Policy.AllowSafeDocsOpen -eq $false) {
            $Status = 'Passed'
            $Result = "Click through is disabled for Safe Documents.`n`n"
            $Result += "**AllowSafeDocsOpen:** $($Policy.AllowSafeDocsOpen)"
        } else {
            $Status = 'Failed'
            $Result = "Click through is enabled for Safe Documents.`n`n"
            $Result += "**AllowSafeDocsOpen:** $($Policy.AllowSafeDocsOpen)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA234' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Click through is disabled for Safe Documents' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA234' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Click through is disabled for Safe Documents' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Safe Attachments'
    }
}
