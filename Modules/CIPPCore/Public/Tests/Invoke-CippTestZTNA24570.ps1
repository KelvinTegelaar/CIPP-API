function Invoke-CippTestZTNA24570 {
    <#
    .SYNOPSIS
    Checks if Entra Connect uses a service principal instead of a user account

    .DESCRIPTION
    Verifies that if hybrid identity synchronization is enabled (Entra Connect), the
    Directory Synchronization Accounts role contains only service principals and not user accounts,
    reducing the risk of credential theft.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        # Get organization info to check if hybrid identity is enabled
        $OrgInfo = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Organization'

        if (-not $OrgInfo) {
            Add-CippTestResult -TestId 'ZTNA24570' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status 'Skipped' `
                -ResultMarkdown 'Unable to retrieve organization information from cache.' `
                -Risk 'High' -Name 'Entra Connect uses a service principal' `
                -UserImpact 'Medium' -ImplementationEffort 'High' `
                -Category 'Access control'
            return
        }

        # Check if hybrid identity is enabled
        $HybridEnabled = $OrgInfo.onPremisesSyncEnabled -eq $true

        if (-not $HybridEnabled) {
            Add-CippTestResult -TestId 'ZTNA24570' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status 'Skipped' `
                -ResultMarkdown '✅ **N/A**: Hybrid identity synchronization is not enabled in this tenant.' `
                -Risk 'High' -Name 'Entra Connect uses a service principal' `
                -UserImpact 'Medium' -ImplementationEffort 'High' `
                -Category 'Access control'
            return
        }

        # Get roles to find Directory Synchronization Accounts role
        $Roles = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Roles'

        if (-not $Roles) {
            Add-CippTestResult -TestId 'ZTNA24570' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status 'Skipped' `
                -ResultMarkdown 'Unable to retrieve roles from cache.' `
                -Risk 'High' -Name 'Entra Connect uses a service principal' `
                -UserImpact 'Medium' -ImplementationEffort 'High' `
                -Category 'Access control'
            return
        }

        # Find Directory Synchronization Accounts role (roleTemplateId: d29b2b05-8046-44ba-8758-1e26182fcf32)
        $DirSyncRole = $null
        foreach ($role in $Roles) {
            if ($role.roleTemplateId -eq 'd29b2b05-8046-44ba-8758-1e26182fcf32') {
                $DirSyncRole = $role
                break
            }
        }

        if (-not $DirSyncRole) {
            Add-CippTestResult -TestId 'ZTNA24570' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status 'Failed' `
                -ResultMarkdown '❌ **Error**: Unable to find Directory Synchronization Accounts role in cache.' `
                -Risk 'High' -Name 'Entra Connect uses a service principal' `
                -UserImpact 'Medium' -ImplementationEffort 'High' `
                -Category 'Access control'
            return
        }

        # Check role members for enabled user accounts
        $EnabledUsers = [System.Collections.Generic.List[object]]::new()
        if ($DirSyncRole.members) {
            foreach ($member in $DirSyncRole.members) {
                # Check if it's a user (not a service principal) and if it's enabled
                if ($member.'@odata.type' -eq '#microsoft.graph.user') {
                    $isEnabled = $member.accountEnabled -eq $true
                    if ($isEnabled) {
                        $EnabledUsers.Add([PSCustomObject]@{
                                DisplayName       = $member.displayName
                                UserPrincipalName = $member.userPrincipalName
                                AccountEnabled    = $isEnabled
                            })
                    }
                }
            }
        }

        $Status = if ($EnabledUsers.Count -eq 0) { 'Passed' } else { 'Failed' }

        # Build result markdown
        $lastSyncDate = if ($OrgInfo.onPremisesLastSyncDateTime) {
            try {
                $date = [DateTime]::Parse($OrgInfo.onPremisesLastSyncDateTime)
                $date.ToString('yyyy-MM-dd HH:mm')
            } catch {
                $OrgInfo.onPremisesLastSyncDateTime
            }
        } else {
            'Never'
        }

        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: Hybrid identity is enabled and using a service principal for synchronization.`n`n"
            $ResultMarkdown += "**Last Sync**: $lastSyncDate`n`n"
            $ResultMarkdown += '[Review configuration](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles)'
        } else {
            $ResultMarkdown = "❌ **Fail**: Hybrid identity is enabled but using $($EnabledUsers.Count) enabled user account(s) for synchronization.`n`n"
            $ResultMarkdown += "**Last Sync**: $lastSyncDate`n`n"
            $ResultMarkdown += "## Directory Synchronization Accounts role members`n`n"
            $ResultMarkdown += "| Display Name | User Principal Name | Enabled |`n"
            $ResultMarkdown += "| :----------- | :------------------ | :------ |`n"

            foreach ($user in $EnabledUsers) {
                $ResultMarkdown += "| $($user.DisplayName) | $($user.UserPrincipalName) | ✅ Yes |`n"
            }

            $ResultMarkdown += "`n[Migrate to service principal](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles)"
        }

        Add-CippTestResult -TestId 'ZTNA24570' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status $Status `
            -ResultMarkdown $ResultMarkdown `
            -Risk 'High' -Name 'Entra Connect uses a service principal' `
            -UserImpact 'Medium' -ImplementationEffort 'High' `
            -Category 'Access control'

    } catch {
        Add-CippTestResult -TestId 'ZTNA24570' -TenantFilter $Tenant -TestType 'ZeroTrustNetworkAccess' -Status 'Failed' `
            -ResultMarkdown "❌ **Error**: $($_.Exception.Message)" `
            -Risk 'High' -Name 'Entra Connect uses a service principal' `
            -UserImpact 'Medium' -ImplementationEffort 'High' `
            -Category 'Access control'
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA24570 failed: $($_.Exception.Message)" -sev Error
    }
}
