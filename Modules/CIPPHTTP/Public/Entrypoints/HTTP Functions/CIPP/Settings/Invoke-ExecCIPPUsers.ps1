function Invoke-ExecCIPPUsers {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Action = $Request.Query.Action ?? $Request.Body.Action
    $Table = Get-CippTable -tablename 'allowedUsers'

    # Returns $true if a row carries a manually-assigned 'superadmin' role.
    # Superadmin granted via Entra group sync (AutoRoles) does NOT count — group
    # membership can change, so it must never be the sole source of superadmin.
    # Match is case-sensitive: the built-in role is exactly 'superadmin'; a custom
    # role like 'SuperAdmin' is a different role and must not trip this protection.
    $HasManualSuperAdmin = {
        param($Entity)
        if (-not $Entity.ManualRoles) { return $false }
        try { return (@($Entity.ManualRoles | ConvertFrom-Json -ErrorAction Stop) -ccontains 'superadmin') }
        catch { return $false }
    }

    switch ($Action) {
        'AddUpdate' {
            try {
                $UPN = $Request.Body.UPN
                if ([string]::IsNullOrWhiteSpace($UPN)) {
                    throw 'UPN (email) is required'
                }
                # Squash casing so the RowKey is canonical and case-variant duplicates can't form
                $UPN = $UPN.Trim().ToLower()

                $Roles = @($Request.Body.Roles)
                if ($Roles.Count -eq 0) {
                    throw 'At least one role must be assigned'
                }

                # Validate roles exist (built-in + custom)
                $CippRolesJson = Join-Path -Path $env:CIPPRootPath -ChildPath 'Config\cipp-roles.json'
                $BuiltInRoles = if (Test-Path $CippRolesJson) {
                    ([System.IO.File]::ReadAllText($CippRolesJson) | ConvertFrom-Json).PSObject.Properties.Name
                } else {
                    @('readonly', 'editor', 'admin', 'superadmin')
                }

                $CustomRolesTable = Get-CippTable -tablename 'CustomRoles'
                $CustomRoles = @((Get-CIPPAzDataTableEntity @CustomRolesTable).RowKey)
                $AllValidRoles = @($BuiltInRoles) + @($CustomRoles) + @('anonymous', 'authenticated')

                foreach ($Role in $Roles) {
                    if ($Role -notin $AllValidRoles) {
                        throw "Invalid role: $Role. Valid roles: $($AllValidRoles -join ', ')"
                    }
                }

                # Find every existing row for this user (case-insensitive) so auto-synced
                # roles are preserved and any case-variant duplicates collapse into one
                # canonical lowercase row.
                $AllUsers = @(Get-CIPPAzDataTableEntity @Table | Where-Object { -not $_.RowKey.StartsWith('_') })
                $MatchingEntities = @($AllUsers | Where-Object { $_.RowKey -and $_.RowKey.ToLower() -eq $UPN })

                # Invariant: at least one user must always keep a manually-assigned superadmin.
                # Block an update that would strip the last manual superadmin.
                if (@($Roles) -cnotcontains 'superadmin') {
                    $TargetHadManualSuperAdmin = @($MatchingEntities | Where-Object { & $HasManualSuperAdmin $_ }).Count -gt 0
                    if ($TargetHadManualSuperAdmin) {
                        $OtherManualSuperAdmins = @($AllUsers | Where-Object { $_.RowKey.ToLower() -ne $UPN -and (& $HasManualSuperAdmin $_) })
                        if ($OtherManualSuperAdmins.Count -eq 0) {
                            throw 'Cannot remove the superadmin role from the last user that has it manually assigned. Grant superadmin manually to another user first (superadmin from Entra group sync does not count).'
                        }
                    }
                }

                # Preserve + merge auto roles across all case-variants (case-sensitive dedupe)
                $AutoRoles = [System.Collections.Generic.List[string]]::new()
                foreach ($Existing in $MatchingEntities) {
                    if ($Existing.AutoRoles) {
                        try {
                            foreach ($R in @($Existing.AutoRoles | ConvertFrom-Json -ErrorAction Stop)) {
                                if (-not $AutoRoles.Contains($R)) { $AutoRoles.Add($R) }
                            }
                        } catch {}
                    }
                }
                $Source = if ($AutoRoles.Count -gt 0) { 'Both' } else { 'Manual' }

                # Compute effective roles = manual ∪ auto (case-sensitive dedupe)
                $EffectiveRoles = [System.Collections.Generic.List[string]]::new()
                foreach ($R in $Roles) { if (-not $EffectiveRoles.Contains($R)) { $EffectiveRoles.Add($R) } }
                foreach ($R in $AutoRoles) { if (-not $EffectiveRoles.Contains($R)) { $EffectiveRoles.Add($R) } }
                $EffectiveRolesArray = @($EffectiveRoles | Sort-Object)

                $Entity = @{
                    PartitionKey = 'User'
                    RowKey       = $UPN
                    Roles        = [string]($EffectiveRolesArray | ConvertTo-Json -Compress -AsArray)
                    ManualRoles  = [string](@($Roles) | ConvertTo-Json -Compress -AsArray)
                    AutoRoles    = [string](@($AutoRoles) | ConvertTo-Json -Compress -AsArray)
                    Source       = $Source
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

                # Remove any case-variant duplicate rows now merged into the canonical row
                foreach ($Existing in $MatchingEntities) {
                    if ($Existing.RowKey -cne $UPN) {
                        Remove-AzDataTableEntity -Force @Table -Entity $Existing
                    }
                }

                # Trigger a user sync to reconcile auto + manual roles
                try { Start-UserSyncTimer } catch {}

                # Invalidate the in-memory user cache so changes apply immediately
                try { [Craft.Services.AuthBridge]::InvalidateUsers() } catch {}

                $Result = "Successfully added/updated user $UPN with roles: $($Roles -join ', ')"
                Write-LogMessage -API $APIName -headers $Headers -message $Result -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to add/update user: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        'Delete' {
            try {
                $UPN = $Request.Body.UPN
                if ([string]::IsNullOrWhiteSpace($UPN)) {
                    throw 'UPN (email) is required'
                }
                $UPN = $UPN.Trim().ToLower()

                # Self-lockout protection: prevent removing yourself
                $CurrentUser = $Request.Headers.'x-ms-client-principal-name'
                if ($CurrentUser -and $UPN -ieq $CurrentUser) {
                    throw 'Cannot remove your own user account. This would lock you out.'
                }

                # Fetch all users once so we can locate the target (case-insensitively)
                # and enforce the "at least one manual superadmin" invariant.
                $AllUsers = @(Get-CIPPAzDataTableEntity @Table | Where-Object { -not $_.RowKey.StartsWith('_') })
                $MatchingEntities = @($AllUsers | Where-Object { $_.RowKey -and $_.RowKey.ToLower() -eq $UPN })
                if ($MatchingEntities.Count -eq 0) {
                    throw "User $UPN not found in the allowed users table"
                }

                # Invariant: don't remove the last user holding a manually-assigned superadmin.
                # (Superadmin granted via Entra group sync does not count — it can disappear
                # when group membership changes.)
                $TargetHasManualSuperAdmin = @($MatchingEntities | Where-Object { & $HasManualSuperAdmin $_ }).Count -gt 0
                if ($TargetHasManualSuperAdmin) {
                    $OtherManualSuperAdmins = @($AllUsers | Where-Object { $_.RowKey.ToLower() -ne $UPN -and (& $HasManualSuperAdmin $_) })
                    if ($OtherManualSuperAdmins.Count -eq 0) {
                        throw 'Cannot remove the last user with a manually assigned superadmin role. Grant superadmin manually to another user first (superadmin from Entra group sync does not count).'
                    }
                }

                foreach ($Existing in $MatchingEntities) {
                    Remove-AzDataTableEntity -Force @Table -Entity $Existing
                }
                try { [Craft.Services.AuthBridge]::InvalidateUsers() } catch {}

                $Result = "Successfully removed user $UPN"
                Write-LogMessage -API $APIName -headers $Headers -message $Result -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to delete user: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        default {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Unknown action: $Action. Valid actions: AddUpdate, Delete" }
            }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Result }
    }
}
