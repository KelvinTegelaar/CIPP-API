function Invoke-ListCustomRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists custom RBAC roles defined in CIPP, including their permission sets and associated access role groups.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $DefaultRoles = @('readonly', 'editor', 'admin', 'superadmin')
    $Table = Get-CippTable -tablename 'CustomRoles'
    $CustomRoles = Get-CIPPAzDataTableEntity @Table

    $AccessRoleGroupTable = Get-CippTable -tablename 'AccessRoleGroups'
    $RoleGroups = Get-CIPPAzDataTableEntity @AccessRoleGroupTable

    $AccessIPRangeTable = Get-CippTable -tablename 'AccessIPRanges'
    $AccessIPRanges = Get-CIPPAzDataTableEntity @AccessIPRangeTable

    $TenantList = Get-Tenants -IncludeErrors

    $RoleList = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($Role in $DefaultRoles) {
        $RoleGroup = $RoleGroups | Where-Object -Property RowKey -EQ $Role

        $IPRangeEntity = $AccessIPRanges | Where-Object -Property RowKey -EQ $Role
        if ($IPRangeEntity) {
            try {
                $IPRanges = @($IPRangeEntity.IPRanges | ConvertFrom-Json)
            } catch {
                $IPRanges = @()
            }
        } else {
            $IPRanges = @()
        }

        $RoleList.Add([pscustomobject]@{
                RoleName       = $Role
                Type           = 'Built-In'
                Permissions    = ''
                AllowedTenants = @('AllTenants')
                BlockedTenants = @()
                EntraGroup     = $RoleGroup.GroupName ?? $null
                EntraGroupId   = $RoleGroup.GroupId ?? $null
                IPRange        = $IPRanges
            })
    }
    foreach ($Role in $CustomRoles) {
        $Role | Add-Member -NotePropertyName RoleName -NotePropertyValue $Role.RowKey -Force
        $Role | Add-Member -NotePropertyName Type -NotePropertyValue 'Custom' -Force

        if ($Role.Permissions) {
            try {
                $Role.Permissions = $Role.Permissions | ConvertFrom-Json
            } catch {
                $Role.Permissions = ''
            }
        }
        if ($Role.AllowedTenants) {
            $RawAllowedTenants = $Role.AllowedTenants
            try {
                # No null filter and no 'AllTenants' fallback: every stored entry produces exactly
                # one displayed entry, so the list shown is the list stored
                $Role.AllowedTenants = @(
                    $RawAllowedTenants | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
                        Resolve-CippRoleTenantEntry -Entry $_ -TenantList $TenantList
                    }
                )
            } catch {
                Write-Warning "Could not parse AllowedTenants for role '$($Role.RowKey)': $($_.Exception.Message)"
                $Role.AllowedTenants = @(
                    [PSCustomObject]@{
                        type       = 'Tenant'
                        value      = [string]$RawAllowedTenants
                        label      = 'Stored value could not be read'
                        Unresolved = $true
                    }
                )
            }
        } else {
            $Role | Add-Member -NotePropertyName AllowedTenants -NotePropertyValue @() -Force
        }
        if ($Role.BlockedTenants) {
            $RawBlockedTenants = $Role.BlockedTenants
            try {
                # An unresolvable id here is exactly the case that mattered: a block on a tenant
                # the current tenant list does not contain used to render as no block at all
                $Role.BlockedTenants = @(
                    $RawBlockedTenants | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
                        Resolve-CippRoleTenantEntry -Entry $_ -TenantList $TenantList
                    }
                )
            } catch {
                Write-Warning "Could not parse BlockedTenants for role '$($Role.RowKey)': $($_.Exception.Message)"
                $Role.BlockedTenants = @(
                    [PSCustomObject]@{
                        type       = 'Tenant'
                        value      = [string]$RawBlockedTenants
                        label      = 'Stored value could not be read'
                        Unresolved = $true
                    }
                )
            }
        } else {
            $Role | Add-Member -NotePropertyName BlockedTenants -NotePropertyValue @() -Force
        }

        $RoleGroup = $RoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey
        if ($RoleGroup) {
            $EntraGroup = $RoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey | Select-Object GroupName, GroupId
            $Role | Add-Member -NotePropertyName EntraGroup -NotePropertyValue $EntraGroup.GroupName -Force
            $Role | Add-Member -NotePropertyName EntraGroupId -NotePropertyValue $EntraGroup.GroupId -Force
        }
        $RoleList.Add($Role)
    }
    $Body = @($RoleList)

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -InputObject $Body -Depth 5
        })
}

