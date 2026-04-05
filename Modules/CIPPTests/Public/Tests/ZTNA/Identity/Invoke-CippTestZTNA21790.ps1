function Invoke-CippTestZTNA21790 {
    <#
    .SYNOPSIS
    Outbound cross-tenant access settings are configured
    #>
    param($Tenant)
    #tested
    try {
        $CrossTenantPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'CrossTenantAccessPolicy'

        if (-not $CrossTenantPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21790' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Outbound cross-tenant access settings are configured' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Application Management'
            return
        }

        $B2BCollabOutbound = $CrossTenantPolicy.b2bCollaborationOutbound.usersAndGroups.accessType -eq 'blocked' -and
        $CrossTenantPolicy.b2bCollaborationOutbound.usersAndGroups.targets[0].target -eq 'AllUsers' -and
        $CrossTenantPolicy.b2bCollaborationOutbound.applications.accessType -eq 'blocked' -and
        $CrossTenantPolicy.b2bCollaborationOutbound.applications.targets[0].target -eq 'AllApplications'

        $B2BDirectOutbound = $CrossTenantPolicy.b2bDirectConnectOutbound.usersAndGroups.accessType -eq 'blocked' -and
        $CrossTenantPolicy.b2bDirectConnectOutbound.usersAndGroups.targets[0].target -eq 'AllUsers' -and
        $CrossTenantPolicy.b2bDirectConnectOutbound.applications.accessType -eq 'blocked' -and
        $CrossTenantPolicy.b2bDirectConnectOutbound.applications.targets[0].target -eq 'AllApplications'

        if ($B2BCollabOutbound -and $B2BDirectOutbound) {
            $Status = 'Passed'
            $Result = 'Default cross-tenant access outbound policy blocks all access'
        } else {
            $Status = 'Failed'
            $Result = 'Default cross-tenant access outbound policy has unrestricted access'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21790' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Outbound cross-tenant access settings are configured' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21790' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Outbound cross-tenant access settings are configured' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Application Management'
    }
}
