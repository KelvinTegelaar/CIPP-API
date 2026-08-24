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
        # Load the role-to-group mappings
        $AccessGroupsTable = Get-CippTable -TableName AccessRoleGroups
        $AccessGroups = @(Get-CIPPAzDataTableEntity @AccessGroupsTable -Filter "PartitionKey eq 'AccessRoleGroups'")

        # Load the roles that actually exist on this instance. A mapping whose role was never
        # migrated across (or was later deleted) leaves an orphaned auto-role that the access
        # check cannot resolve - which locks the user out of everything, base role included.
        # Skipping those mappings here lets the sync self-heal: because each user's auto-roles
        # are recomputed from scratch every run, the stale role is dropped from every affected
        # user on the next pass instead of being re-stamped forever. This mirrors the same
        # existence guard the live path already applies in Test-CIPPAccessUserRole.
        # $CustomRoleNames stays $null when the lookup fails so a transient storage error
        # degrades to "prune nothing" rather than stripping every custom role from every user.
        $BaseRoles = @('superadmin', 'admin', 'editor', 'readonly')
        $CustomRoleNames = $null
        try {
            $CustomRolesTable = Get-CippTable -TableName CustomRoles
            $CustomRoleNames = @(Get-CIPPAzDataTableEntity @CustomRolesTable -Filter "PartitionKey eq 'CustomRoles'" | ForEach-Object { $_.RowKey })
        } catch {
            Write-LogMessage -API $ApiName -tenant 'none' -message "User sync could not load custom roles; skipping stale-role pruning this run: $($_.Exception.Message)" -sev Warning
        }

        # Build a lookup: GroupId -> Role names (a group can map to multiple roles), keeping only
        # roles that still exist. Orphaned role names are collected so the run that prunes them
        # can say which ones, without re-logging on every steady-state pass afterwards.
        $GroupToRoles = @{}
        $SkippedRoles = [System.Collections.Generic.List[string]]::new()
        foreach ($Mapping in $AccessGroups) {
            if (-not $Mapping.GroupId) { continue }
            # $null CustomRoleNames means the lookup failed above - treat every role as valid.
            $RoleExists = ($BaseRoles -contains $Mapping.RowKey) -or ($null -eq $CustomRoleNames) -or ($CustomRoleNames -contains $Mapping.RowKey)
            if (-not $RoleExists) {
                if ($SkippedRoles -notcontains $Mapping.RowKey) { $SkippedRoles.Add($Mapping.RowKey) }
                continue
            }
            if (-not $GroupToRoles.ContainsKey($Mapping.GroupId)) {
                $GroupToRoles[$Mapping.GroupId] = [System.Collections.Generic.List[string]]::new()
            }
            $GroupToRoles[$Mapping.GroupId].Add($Mapping.RowKey)
        }

        # Only fetch members of groups that still map to at least one real role
        $RoleGroupIds = @($GroupToRoles.Keys)

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
                        $UserRoleMap[$Upn] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
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

        # Load existing allowedUsers table
        $UsersTable = Get-CippTable -tablename 'allowedUsers'
        $ExistingUsers = @(Get-CIPPAzDataTableEntity @UsersTable | Where-Object { -not $_.RowKey.StartsWith('_') })

        # Group existing rows by lowercased UPN so case-variant duplicate rows
        # are reconciled into one canonical row.
        $ExistingLookup = @{}
        foreach ($Existing in $ExistingUsers) {
            $Key = $Existing.RowKey.ToLower()
            if (-not $ExistingLookup.ContainsKey($Key)) {
                $ExistingLookup[$Key] = [System.Collections.Generic.List[object]]::new()
            }
            $ExistingLookup[$Key].Add($Existing)
        }

        $Now = (Get-Date).ToUniversalTime().ToString('o')
        $RemoveCount = 0
        $EntitiesToUpsert = [System.Collections.Generic.List[object]]::new()
        $EntitiesToRemove = [System.Collections.Generic.List[object]]::new()

        # Upsert users that are members of a mapped role group
        foreach ($Upn in $UserRoleMap.Keys) {
            $AutoRoles = @($UserRoleMap[$Upn] | Sort-Object)

            # Merge manual roles from every case-variant of this user (case-sensitive dedupe)
            $ManualRoles = [System.Collections.Generic.List[string]]::new()
            if ($ExistingLookup.ContainsKey($Upn)) {
                foreach ($Existing in $ExistingLookup[$Upn]) {
                    if ($Existing.ManualRoles) {
                        try {
                            foreach ($R in @($Existing.ManualRoles | ConvertFrom-Json -ErrorAction Stop)) {
                                if (-not $ManualRoles.Contains($R)) { $ManualRoles.Add($R) }
                            }
                        } catch {}
                    }
                    # Any row that isn't the canonical lowercase key is a duplicate to remove
                    if ($Existing.RowKey -cne $Upn) { $EntitiesToRemove.Add($Existing) }
                }
            }
            $Source = if ($ManualRoles.Count -gt 0) { 'Both' } else { 'Auto' }

            # Compute effective roles = auto ∪ manual (case-sensitive dedupe)
            $EffectiveRoles = [System.Collections.Generic.List[string]]::new()
            foreach ($Role in $AutoRoles) { if (-not $EffectiveRoles.Contains($Role)) { $EffectiveRoles.Add($Role) } }
            foreach ($Role in $ManualRoles) { if (-not $EffectiveRoles.Contains($Role)) { $EffectiveRoles.Add($Role) } }
            $EffectiveRolesArray = @($EffectiveRoles | Sort-Object)

            $Entity = @{
                PartitionKey = 'User'
                RowKey       = $Upn
                Roles        = [string]($EffectiveRolesArray | ConvertTo-Json -Compress -AsArray)
                AutoRoles    = [string](@($AutoRoles) | ConvertTo-Json -Compress -AsArray)
                ManualRoles  = [string]((($ManualRoles.Count -gt 0) ? @($ManualRoles) : @()) | ConvertTo-Json -Compress -AsArray)
                Source       = $Source
                LastSync     = $Now
            }

            $EntitiesToUpsert.Add($Entity)
        }

        # Reconcile existing users that are NOT in any mapped role group
        foreach ($Key in $ExistingLookup.Keys) {
            if ($UserRoleMap.ContainsKey($Key)) { continue } # Still in a group, already handled

            $Variants = $ExistingLookup[$Key]
            $NeedsNormalize = ($Variants.Count -gt 1) -or ($Variants[0].RowKey -cne $Key)

            # Merge manual roles across all case-variants (case-sensitive dedupe)
            $ManualRoles = [System.Collections.Generic.List[string]]::new()
            foreach ($Existing in $Variants) {
                if ($Existing.ManualRoles) {
                    try {
                        foreach ($R in @($Existing.ManualRoles | ConvertFrom-Json -ErrorAction Stop)) {
                            if (-not $ManualRoles.Contains($R)) { $ManualRoles.Add($R) }
                        }
                    } catch {}
                }
            }

            if (-not $NeedsNormalize) {
                # Single clean lowercase row — apply the original cleanup rules
                $Existing = $Variants[0]
                if ($Existing.Source -eq 'Auto') {
                    # Purely auto-provisioned user no longer in any group — remove
                    $EntitiesToRemove.Add($Existing)
                } elseif ($Existing.Source -eq 'Both') {
                    if ($ManualRoles.Count -gt 0) {
                        # Was both auto + manual — clear auto roles, keep manual only
                        $ManualArray = @($ManualRoles | Sort-Object)
                        $EntitiesToUpsert.Add(@{
                            PartitionKey = 'User'
                            RowKey       = $Key
                            Roles        = [string]($ManualArray | ConvertTo-Json -Compress -AsArray)
                            AutoRoles    = '[]'
                            ManualRoles  = [string]($ManualArray | ConvertTo-Json -Compress -AsArray)
                            Source       = 'Manual'
                            LastSync     = $Now
                        })
                    } else {
                        $EntitiesToRemove.Add($Existing)
                    }
                }
                # Source = 'Manual' (or unset) — leave untouched, these are purely manual entries
                continue
            }

            # Duplicates or non-lowercase casing present — collapse to one canonical lowercase row
            if ($ManualRoles.Count -gt 0) {
                $ManualArray = @($ManualRoles | Sort-Object)
                $EntitiesToUpsert.Add(@{
                    PartitionKey = 'User'
                    RowKey       = $Key
                    Roles        = [string]($ManualArray | ConvertTo-Json -Compress -AsArray)
                    AutoRoles    = '[]'
                    ManualRoles  = [string]($ManualArray | ConvertTo-Json -Compress -AsArray)
                    Source       = 'Manual'
                    LastSync     = $Now
                })
                # Remove every case-variant except the canonical one (overwritten by the upsert)
                foreach ($Existing in $Variants) {
                    if ($Existing.RowKey -cne $Key) { $EntitiesToRemove.Add($Existing) }
                }
            } else {
                # No manual roles anywhere — purely auto-provisioned; remove all variants
                foreach ($Existing in $Variants) { $EntitiesToRemove.Add($Existing) }
            }
        }

        # Apply upserts first (write canonical rows), then removals (drop duplicates/stale rows).
        # Only count an upsert as a change when the role data actually differs from the
        # existing canonical row — LastSync alone changing every run isn't a real change.
        $ChangedCount = 0
        foreach ($Entity in $EntitiesToUpsert) {
            $Canonical = $null
            if ($ExistingLookup.ContainsKey($Entity.RowKey)) {
                $Canonical = $ExistingLookup[$Entity.RowKey] | Where-Object { $_.RowKey -ceq $Entity.RowKey } | Select-Object -First 1
            }
            if (-not $Canonical -or
                $Canonical.Roles -ne $Entity.Roles -or
                $Canonical.AutoRoles -ne $Entity.AutoRoles -or
                $Canonical.ManualRoles -ne $Entity.ManualRoles -or
                $Canonical.Source -ne $Entity.Source) {
                $ChangedCount++
            }
            Add-CIPPAzDataTableEntity @UsersTable -Entity $Entity -Force
        }
        foreach ($Entity in $EntitiesToRemove) {
            Remove-CIPPAzDataTableEntity -Force @UsersTable -Entity $Entity
            $RemoveCount++
        }

        # Invalidate CRAFT's in-memory user cache so changes apply
        try { [Craft.Services.AuthBridge]::InvalidateUsers() } catch {}

        # Only log when something actually changed — no noise on steady-state runs.
        if ($ChangedCount -gt 0 -or $RemoveCount -gt 0) {
            $Message = "User sync completed: $ChangedCount users added/updated, $RemoveCount duplicate/stale rows removed."
            if ($SkippedRoles.Count -gt 0) {
                $Message += " Pruned auto-role(s) with no matching definition on this instance: $($SkippedRoles -join ', ')."
            }
            Write-LogMessage -API $ApiName -tenant 'none' -message $Message -sev Info
        }

    } catch {
        $ErrorData = Get-CippException -Exception $_
        Write-LogMessage -API $ApiName -tenant 'none' -message "User sync failed: $($ErrorData.NormalizedError)" -sev Error -LogData $ErrorData
    }
}
