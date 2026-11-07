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
        $Users = Get-CIPPTestData -TenantFilter $Tenant -Type 'Users'
        $UserById = [CIPP.CippIndex]::Build($Users, @(foreach ($U in $Users) { , ($($U.id) ?? $null) }))

        $MembersByRole = [ordered]@{}
        $GroupIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Role in $PrivilegedRoles) {
            $RoleMembers = Get-CippDbRoleMembers -TenantFilter $Tenant -RoleTemplateId $Role.RoletemplateId
            $MembersByRole[$Role.displayName] = $RoleMembers
            foreach ($Member in $RoleMembers) {
                if ($Member.'@odata.type' -eq '#microsoft.graph.group' -and $Member.id) { [void]$GroupIds.Add([string]$Member.id) }
            }
        }

        # Members are streamed: kept for every group they are too large to cache, so only role-assigned groups are kept
        $GroupsById = @{}
        if ($GroupIds.Count -gt 0) {
            Get-CIPPTestData -TenantFilter $Tenant -Type 'Groups' -Fields 'id', 'members' -Stream | ForEach-Object {
                if ($GroupIds.Contains([string]$_.id)) { $GroupsById[[string]$_.id] = $_ }
            }
        }

        $RoleData = [System.Collections.Generic.List[object]]::new()
        $SeenRows = [System.Collections.Generic.HashSet[string]]::new()
        $UnresolvedGroups = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($RoleName in $MembersByRole.Keys) {
            foreach ($Member in $MembersByRole[$RoleName]) {
                $Principals = if ($Member.'@odata.type' -eq '#microsoft.graph.user') {
                    $Member
                } elseif ($Member.'@odata.type' -eq '#microsoft.graph.group') {
                    $Group = $GroupsById[[string]$Member.id]
                    if (-not $Group) { [void]$UnresolvedGroups.Add([string]$Member.id) }
                    foreach ($GroupMember in $Group.members) {
                        if ($GroupMember.'@odata.type' -eq '#microsoft.graph.user') { $GroupMember }
                    }
                }
                foreach ($Principal in $Principals) {
                    if (-not $SeenRows.Add("$RoleName|$($Principal.id)")) { continue }
                    $UserDetail = $UserById.First($Principal.id)
                    $RoleData.Add([PSCustomObject]@{
                            RoleName              = $RoleName
                            UserId                = $Principal.id
                            UserDisplayName       = if ($UserDetail) { $UserDetail.displayName } else { $Principal.displayName }
                            UserRecordFound       = [bool]$UserDetail
                            OnPremisesSyncEnabled = $UserDetail.onPremisesSyncEnabled -eq $true
                        })
                }
            }
        }

        $SyncedUserIds = [System.Collections.Generic.HashSet[string]]::new()
        $MissingUserIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Row in $RoleData) {
            if (-not $Row.UserRecordFound) { [void]$MissingUserIds.Add([string]$Row.UserId) }
            elseif ($Row.OnPremisesSyncEnabled) { [void]$SyncedUserIds.Add([string]$Row.UserId) }
        }

        $UnresolvedReasons = @(
            if ($MissingUserIds.Count -eq 1) { 'User data is missing for 1 role principal.' }
            elseif ($MissingUserIds.Count -gt 1) { "User data is missing for $($MissingUserIds.Count) role principals." }
            if ($UnresolvedGroups.Count -eq 1) { 'Membership could not be resolved for 1 privileged group.' }
            elseif ($UnresolvedGroups.Count -gt 1) { "Membership could not be resolved for $($UnresolvedGroups.Count) privileged groups." }
        )

        if ($SyncedUserIds.Count -gt 0) {
            $Status = 'Failed'
            $UserLabel = if ($SyncedUserIds.Count -eq 1) { 'user who is' } else { 'users who are' }
            $ResultMarkdown = [System.Text.StringBuilder]::new("This tenant has $($SyncedUserIds.Count) distinct privileged $UserLabel synced from on-premises.`n`n")
            if ($UnresolvedReasons.Count -gt 0) { $null = $ResultMarkdown.Append("$($UnresolvedReasons -join ' ')`n`n") }
        } elseif ($UnresolvedReasons.Count -gt 0) {
            $Status = 'Investigate'
            $ResultMarkdown = [System.Text.StringBuilder]::new("$($UnresolvedReasons -join ' ')`n`n")
        } else {
            $Status = 'Passed'
            $ResultMarkdown = [System.Text.StringBuilder]::new("Validated that standing or eligible privileged accounts are cloud only accounts.`n`n")
        }

        if ($RoleData.Count -gt 0) {
            $ExceptionRows = @($RoleData.Where({ -not $_.UserRecordFound -or $_.OnPremisesSyncEnabled }))
            $SourceRows = if ($ExceptionRows.Count -gt 0) { $ExceptionRows } else { $RoleData }
            $Limit = if ($ExceptionRows.Count -gt 0) { 50 } else { 10 }
            $ReportRows = @($SourceRows | Sort-Object RoleName, UserDisplayName).Where({ $true }, 'First', $Limit)

            $null = $ResultMarkdown.Append("## Privileged roles`n`n")
            $null = $ResultMarkdown.Append("| Role name | User | Source | Status |`n")
            $null = $ResultMarkdown.Append("| :--- | :--- | :--- | :---: |`n")
            foreach ($RoleUser in $ReportRows) {
                $Type, $Mark = if (-not $RoleUser.UserRecordFound) { 'User data unavailable', '⚠️' }
                elseif ($RoleUser.OnPremisesSyncEnabled) { 'Synced from on-premises', '❌' }
                else { 'Cloud native identity', '✅' }
                $UserLink = "https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/$($RoleUser.UserId)"
                $null = $ResultMarkdown.Append("| $($RoleUser.RoleName) | [$($RoleUser.UserDisplayName)]($UserLink) | $Type | $Mark |`n")
            }
            if ($SourceRows.Count -gt $ReportRows.Count) {
                $Kind = if ($ExceptionRows.Count -gt 0) { 'failed or unresolved' } else { 'cloud-only' }
                $null = $ResultMarkdown.Append("`nShowing the first $($ReportRows.Count) of $($SourceRows.Count) $Kind privileged role assignments; additional rows were omitted.`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Privileged accounts are cloud native identities' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Privileged accounts are cloud native identities' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged access'
    }
}
