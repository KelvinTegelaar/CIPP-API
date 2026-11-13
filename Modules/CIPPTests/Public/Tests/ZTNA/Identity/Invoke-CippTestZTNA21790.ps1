function Invoke-CippTestZTNA21790 {
    <#
    .SYNOPSIS
    Outbound cross-tenant access settings are configured
    #>
    param($Tenant)
    #tested
    try {
        $CrossTenantPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'CrossTenantAccessPolicy'

        if (-not $CrossTenantPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21790' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Outbound cross-tenant access settings are configured' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Application management'
            return
        }

        $B2BCollabOutbound = $CrossTenantPolicy.b2bCollaborationOutbound.usersAndGroups.accessType -eq 'blocked' -and
        (@($CrossTenantPolicy.b2bCollaborationOutbound.usersAndGroups.targets.target) -contains 'AllUsers') -and
        $CrossTenantPolicy.b2bCollaborationOutbound.applications.accessType -eq 'blocked' -and
        (@($CrossTenantPolicy.b2bCollaborationOutbound.applications.targets.target) -contains 'AllApplications')

        $B2BDirectOutbound = $CrossTenantPolicy.b2bDirectConnectOutbound.usersAndGroups.accessType -eq 'blocked' -and
        (@($CrossTenantPolicy.b2bDirectConnectOutbound.usersAndGroups.targets.target) -contains 'AllUsers') -and
        $CrossTenantPolicy.b2bDirectConnectOutbound.applications.accessType -eq 'blocked' -and
        (@($CrossTenantPolicy.b2bDirectConnectOutbound.applications.targets.target) -contains 'AllApplications')

        $Result = [System.Text.StringBuilder]::new()
        if ($B2BCollabOutbound -and $B2BDirectOutbound) {
            $Status = 'Passed'
            $null = $Result.Append("Tenant has a default cross-tenant access setting outbound policy that blocks access.`n")
        } else {
            $Status = 'Failed'
            $null = $Result.Append("Tenant has a default cross-tenant access setting outbound policy with unrestricted access.`n")
        }

        $null = $Result.Append("`n## [Outbound access settings - Default settings](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/OutboundAccessSettings.ReactView/isDefault~/true/name//id/)`n")
        foreach ($Section in @(@('B2B Collaboration', $CrossTenantPolicy.b2bCollaborationOutbound), @('B2B Direct Connect', $CrossTenantPolicy.b2bDirectConnectOutbound))) {
            $null = $Result.Append("### $($Section[0])`n")
            foreach ($Part in @(@('Users and groups', $Section[1].usersAndGroups), @('External applications', $Section[1].applications))) {
                $Targets = @($Part[1].targets)
                $AppliesTo = if ($Targets.target -contains 'AllUsers') {
                    'All users'
                } elseif ($Targets.target -contains 'AllApplications') {
                    'All external applications'
                } else {
                    $UserCount = $Targets.Where({ $_.targetType -eq 'user' }).Count
                    $GroupCount = $Targets.Where({ $_.targetType -eq 'group' }).Count
                    $AppCount = $Targets.Count - $UserCount - $GroupCount
                    if ($AppCount -gt 0) { "Selected external applications ($AppCount applications)" } else { "Selected users and groups ($UserCount users, $GroupCount groups)" }
                }
                $null = $Result.Append("$($Part[0])`n- Access status: $($Part[1].accessType)`n- Applies to: $AppliesTo`n`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21790' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Outbound cross-tenant access settings are configured' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Application management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21790' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Outbound cross-tenant access settings are configured' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Application management'
    }
}
