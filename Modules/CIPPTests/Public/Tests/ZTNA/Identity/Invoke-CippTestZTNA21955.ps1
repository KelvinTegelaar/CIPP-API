function Invoke-CippTestZTNA21955 {
    <#
    .SYNOPSIS
    Checks that local administrators on Entra joined devices are managed by the organization

    .DESCRIPTION
    Passes when the Microsoft Entra Joined Device Local Administrator role has assigned or eligible
    members. Not applicable to tenants licensed for Intune, which manage local administrators there.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    $TestId = 'ZTNA21955'
    $DeviceLocalAdminRoleId = '9f06204d-73c1-4d4c-880a-6edb90606fd8'
    $TestParams = @{
        TestId               = $TestId
        TenantFilter         = $Tenant
        TestType             = 'Identity'
        Risk                 = 'Medium'
        Name                 = 'Manage local admins on Entra joined devices'
        UserImpact           = 'Low'
        ImplementationEffort = 'Low'
        Category             = 'Device security'
    }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Entra ID P1. Required capabilities: AAD_PREMIUM, AAD_PREMIUM_P2.'
            return
        }
        if (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'Not applicable: this tenant is licensed for Intune, where local administrators on Entra joined devices are managed through device policies.'
            return
        }

        if (-not (Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles')) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $Members = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $DeviceLocalAdminRoleId

        if ($Members.Count -gt 0) {
            $Status = 'Passed'
            $ResultMarkdown = [System.Text.StringBuilder]::new("Local administrators on Microsoft Entra joined devices are managed by the organization.`n")
        } else {
            $Status = 'Failed'
            $ResultMarkdown = [System.Text.StringBuilder]::new("Local administrators on Microsoft Entra joined devices are not managed by the organization.`n`n❌ No assigned or eligible users/groups found for the Microsoft Entra Joined Device Local Administrator role.`n")
        }

        $AssignmentsLink = "https://entra.microsoft.com/#view/Microsoft_Azure_PIMCommon/UserRolesViewModelMenuBlade/~/members/roleObjectId/$DeviceLocalAdminRoleId/roleId/$DeviceLocalAdminRoleId/roleTemplateId/$DeviceLocalAdminRoleId/roleName/Microsoft%20Entra%20Joined%20Device%20Local%20Administrator/isRoleCustom~/false/resourceScopeId/%2F"
        foreach ($Section in @(
                @{ Title = 'Active'; Rows = @($Members.Where({ $_.AssignmentType -ne 'Eligible' })) }
                @{ Title = 'Eligible'; Rows = @($Members.Where({ $_.AssignmentType -eq 'Eligible' })) }
            )) {
            if ($Section.Rows.Count -eq 0) { continue }
            $null = $ResultMarkdown.Append("`n## [$($Section.Title) Microsoft Entra Joined Device Local Administrator assignments]($AssignmentsLink)`n`n")
            $null = $ResultMarkdown.Append("| Display name | UPN | Type | Assignment type |`n")
            $null = $ResultMarkdown.Append("| :----------- | :--- | :--- | :-------------- |`n")
            foreach ($Member in ($Section.Rows | Sort-Object -Property displayName)) {
                $IsUser = $Member.'@odata.type' -eq '#microsoft.graph.user'
                $PortalLink = if ($IsUser) {
                    "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/overview/userId/$($Member.id)"
                } else {
                    "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Overview/groupId/$($Member.id)"
                }
                $Upn = if ([string]::IsNullOrWhiteSpace($Member.userPrincipalName)) { 'N/A' } else { $Member.userPrincipalName }
                $null = $ResultMarkdown.Append("| [$($Member.displayName)]($PortalLink) | $Upn | $(if ($IsUser) { 'User' } else { 'Group' }) | $($Member.AssignmentType) |`n")
            }
        }

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown $ResultMarkdown

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)"
    }
}
