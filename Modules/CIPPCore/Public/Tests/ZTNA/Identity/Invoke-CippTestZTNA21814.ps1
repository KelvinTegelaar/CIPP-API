function Invoke-CippTestZTNA21814 {
    <#
    .SYNOPSIS
    Privileged accounts are cloud native identities
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    $TestId = 'ZTNA21814'

    try {
        $PrivilegedRoles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles
        $Users = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'

        $RoleData = [System.Collections.Generic.List[object]]::new()

        foreach ($Role in $PrivilegedRoles) {
            $RoleMembers = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $Role.RoletemplateId
            $RoleUsers = $RoleMembers | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.user' }

            foreach ($RoleMember in $RoleUsers) {
                $UserDetail = $Users | Where-Object { $_.id -eq $RoleMember.id } | Select-Object -First 1

                if ($UserDetail) {
                    $RoleData.Add([PSCustomObject]@{
                            RoleName              = $Role.displayName
                            UserId                = $UserDetail.id
                            UserDisplayName       = $UserDetail.displayName
                            UserPrincipalName     = $UserDetail.userPrincipalName
                            OnPremisesSyncEnabled = $UserDetail.onPremisesSyncEnabled
                        })
                }
            }
        }

        $SyncedUsers = $RoleData | Where-Object { $_.OnPremisesSyncEnabled -eq $true }
        $Passed = $SyncedUsers.Count -eq 0

        if ($Passed) {
            $ResultMarkdown = "Validated that standing or eligible privileged accounts are cloud only accounts.`n`n"
        } else {
            $ResultMarkdown = "This tenant has $($SyncedUsers.Count) privileged users that are synced from on-premise.`n`n"
        }

        if ($RoleData.Count -gt 0) {
            $ResultMarkdown += "## Privileged Roles`n`n"
            $ResultMarkdown += "| Role Name | User | Source | Status |`n"
            $ResultMarkdown += "| :--- | :--- | :--- | :---: |`n"

            foreach ($RoleUser in ($RoleData | Sort-Object RoleName, UserDisplayName)) {
                if ($RoleUser.OnPremisesSyncEnabled) {
                    $Type = 'Synced from on-premise'
                    $Status = '❌'
                } else {
                    $Type = 'Cloud native identity'
                    $Status = '✅'
                }

                $UserLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($RoleUser.UserId)"
                $ResultMarkdown += "| $($RoleUser.RoleName) | [$($RoleUser.UserDisplayName)]($UserLink) | $Type | $Status |`n"
            }
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Privileged accounts are cloud native identities' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Privileged accounts are cloud native identities' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'
    }
}
