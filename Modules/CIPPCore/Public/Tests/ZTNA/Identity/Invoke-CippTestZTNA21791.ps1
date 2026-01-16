function Invoke-CippTestZTNA21791 {
    <#
    .SYNOPSIS
    Guests cannot invite other guests
    #>
    param($Tenant)
    #tested
    try {
        $AuthPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21791' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Guests cannot invite other guests' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $AllowInvitesFrom = $AuthPolicy.allowInvitesFrom

        if ($AllowInvitesFrom -ne 'everyone') {
            $Status = 'Passed'
            $Result = "Tenant restricts who can invite guests (Set to: $AllowInvitesFrom)"
        } else {
            $Status = 'Failed'
            $Result = 'Tenant allows any user including guests to invite other guests'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21791' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Guests cannot invite other guests' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21791' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guests cannot invite other guests' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
