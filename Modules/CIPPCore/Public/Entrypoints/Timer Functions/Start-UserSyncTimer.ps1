function Start-UserSyncTimer {
    <#
    .SYNOPSIS
        Sync partner tenant users into the allowedUsers table
    .DESCRIPTION
        Pulls users from the partner tenant via Graph, resolves their Entra group memberships
        against AccessRoleGroups, and upserts into allowedUsers with auto-derived roles.
        Manual role assignments are preserved in a separate column and merged at compute time.
    .FUNCTIONALITY
        Entrypoint
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if (-not $PSCmdlet.ShouldProcess('Start-UserSyncTimer', 'Sync partner tenant users to allowedUsers table')) {
        return
    }

    $ApiName = 'UserSync'

    try {
        Write-LogMessage -API $ApiName -tenant 'none' -message 'Starting user sync from partner tenant.' -sev Info

        # Load the role-to-group mappings
        $AccessGroupsTable = Get-CippTable -TableName AccessRoleGroups
        $AccessGroups = @(Get-CIPPAzDataTableEntity @AccessGroupsTable -Filter "PartitionKey eq 'AccessRoleGroups'")

        # Get the group IDs we care about
        $RoleGroupIds = @($AccessGroups | ForEach-Object { $_.GroupId } | Where-Object { $_ })

        # Build a lookup: GroupId -> Role names (a group can map to multiple roles)
        $GroupToRoles = @{}
        foreach ($Mapping in $AccessGroups) {
            if ($Mapping.GroupId) {
                if (-not $GroupToRoles.ContainsKey($Mapping.GroupId)) {
                    $GroupToRoles[$Mapping.GroupId] = [System.Collections.Generic.List[string]]::new()
                }
                $GroupToRoles[$Mapping.GroupId].Add($Mapping.RowKey)
            }
        }

        # Fetch members of each role group from the partner tenant
        # Use transitiveMembers to catch nested group memberships
        $UserRoleMap = @{} # UPN -> HashSet of auto roles

        foreach ($GroupId in $RoleGroupIds) {
            try {
                $Members = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId/transitiveMembers?`$select=id,userPrincipalName,mail,accountEnabled&`$top=999" -NoAuthCheck $true -AsApp $true)
                $UserMembers = @($Members | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.user' -and $_.accountEnabled -eq $true })

                $RolesForGroup = $GroupToRoles[$GroupId]

                foreach ($Member in $UserMembers) {
                    $Upn = $Member.userPrincipalName
                    if ([string]::IsNullOrWhiteSpace($Upn)) { continue }
                    $Upn = $Upn.Trim().ToLower()

                    if (-not $UserRoleMap.ContainsKey($Upn)) {
                        $UserRoleMap[$Upn] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    }
                    foreach ($Role in $RolesForGroup) {
                        [void]$UserRoleMap[$Upn].Add($Role)
                    }
                }
            } catch {
                $ErrorData = Get-CippException -Exception $_
                Write-LogMessage -API $ApiName -tenant 'none' -message "Failed to fetch members of group $GroupId : $($ErrorData.NormalizedError)" -sev Warning -LogData $ErrorData
            }
        }

        if ($UserRoleMap.Count -eq 0 -and $RoleGroupIds.Count -gt 0) {
            Write-LogMessage -API $ApiName -tenant 'none' -message 'No users found in any role groups.' -sev Info
        } elseif ($RoleGroupIds.Count -eq 0) {
            Write-LogMessage -API $ApiName -tenant 'none' -message 'No Entra groups mapped to roles — will clean up any stale auto-provisioned users.' -sev Info
        }

        # Load existing allowedUsers table
        $UsersTable = Get-CippTable -tablename 'allowedUsers'
        $ExistingUsers = @(Get-CIPPAzDataTableEntity @UsersTable | Where-Object { -not $_.RowKey.StartsWith('_') })

        # Build lookup of existing users
        $ExistingLookup = @{}
        foreach ($Existing in $ExistingUsers) {
            $ExistingLookup[$Existing.RowKey.ToLower()] = $Existing
        }

        $Now = (Get-Date).ToUniversalTime().ToString('o')
        $UpsertCount = 0
        $RemoveCount = 0
        $EntitiesToUpsert = [System.Collections.Generic.List[object]]::new()

        # Upsert users from Graph
        foreach ($Upn in $UserRoleMap.Keys) {
            $AutoRoles = @($UserRoleMap[$Upn] | Sort-Object)

            $ManualRoles = @()
            $Source = 'Auto'

            if ($ExistingLookup.ContainsKey($Upn)) {
                $Existing = $ExistingLookup[$Upn]

                # Preserve manual roles if they exist
                if ($Existing.ManualRoles) {
                    try {
                        $ManualRoles = @($Existing.ManualRoles | ConvertFrom-Json -ErrorAction Stop)
                    } catch {
                        $ManualRoles = @()
                    }
                }

                # If user was previously manual-only and now also auto, mark as Both
                if ($ManualRoles.Count -gt 0) {
                    $Source = 'Both'
                }
            }

            # Compute effective roles = union of auto + manual
            $EffectiveRoles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Role in $AutoRoles) { [void]$EffectiveRoles.Add($Role) }
            foreach ($Role in $ManualRoles) { [void]$EffectiveRoles.Add($Role) }
            $EffectiveRolesArray = @($EffectiveRoles | Sort-Object)

            $Entity = @{
                PartitionKey = 'User'
                RowKey       = $Upn
                Roles        = [string]($EffectiveRolesArray | ConvertTo-Json -Compress -AsArray)
                AutoRoles    = [string]($AutoRoles | ConvertTo-Json -Compress -AsArray)
                ManualRoles  = [string](($ManualRoles.Count -gt 0 ? $ManualRoles : @()) | ConvertTo-Json -Compress -AsArray)
                Source       = $Source
                LastSync     = $Now
            }

            $EntitiesToUpsert.Add($Entity)
            $UpsertCount++
        }

        # Handle users that were auto-provisioned but are no longer in any role group
        foreach ($Existing in $ExistingUsers) {
            $ExistingUpn = $Existing.RowKey.ToLower()
            if ($UserRoleMap.ContainsKey($ExistingUpn)) { continue } # Still in a group, already handled

            if ($Existing.Source -eq 'Auto') {
                # Purely auto-provisioned user no longer in any group — remove
                Remove-AzDataTableEntity -Force @UsersTable -Entity $Existing
                $RemoveCount++
            } elseif ($Existing.Source -eq 'Both') {
                # Was both auto + manual — clear auto roles, keep manual only
                $ManualRoles = @()
                if ($Existing.ManualRoles) {
                    try {
                        $ManualRoles = @($Existing.ManualRoles | ConvertFrom-Json -ErrorAction Stop)
                    } catch {
                        $ManualRoles = @()
                    }
                }

                if ($ManualRoles.Count -gt 0) {
                    $Entity = @{
                        PartitionKey = 'User'
                        RowKey       = $Existing.RowKey
                        Roles        = [string]($ManualRoles | ConvertTo-Json -Compress -AsArray)
                        AutoRoles    = '[]'
                        ManualRoles  = [string]($ManualRoles | ConvertTo-Json -Compress -AsArray)
                        Source       = 'Manual'
                        LastSync     = $Now
                    }
                    $EntitiesToUpsert.Add($Entity)
                } else {
                    # No manual roles either — remove
                    Remove-AzDataTableEntity -Force @UsersTable -Entity $Existing
                    $RemoveCount++
                }
            }
            # Source = 'Manual' (or unset) — leave untouched, these are purely manual entries
        }

        # Batch upsert
        if ($EntitiesToUpsert.Count -gt 0) {
            foreach ($Entity in $EntitiesToUpsert) {
                Add-CIPPAzDataTableEntity @UsersTable -Entity $Entity -Force
            }
        }

        # Invalidate CRAFT's in-memory user cache so changes apply
        try { [Craft.Services.AuthBridge]::InvalidateUsers() } catch {}

        Write-LogMessage -API $ApiName -tenant 'none' -message "User sync completed: $UpsertCount users synced, $RemoveCount auto-only users removed." -sev Info

    } catch {
        $ErrorData = Get-CippException -Exception $_
        Write-LogMessage -API $ApiName -tenant 'none' -message "User sync failed: $($ErrorData.NormalizedError)" -sev Error -LogData $ErrorData
    }
}
