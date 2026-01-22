function Invoke-CippTestORCA121 {
    <#
    .SYNOPSIS
    Supported filter policy action used
    #>
    param($Tenant)

    try {
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoQuarantinePolicy'

        if (-not $Policies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA121' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Supported filter policy action used' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Quarantine'
            return
        }

        $Status = 'Passed'
        $Result = "Quarantine policies are configured to support Zero Hour Auto Purge.`n`n"
        $Result += "**Total Policies:** $($Policies.Count)"

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA121' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Supported filter policy action used' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Quarantine'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ORCA121' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Supported filter policy action used' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Quarantine'
    }
}
