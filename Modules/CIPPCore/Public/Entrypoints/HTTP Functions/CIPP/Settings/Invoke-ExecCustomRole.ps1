function Invoke-ExecCustomRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'CustomRoles'
    $AccessRoleGroupTable = Get-CippTable -tablename 'AccessRoleGroups'
    $AccessIPRangeTable = Get-CippTable -tablename 'AccessIPRanges'
    $Action = $Request.Query.Action ?? $Request.Body.Action

    $CIPPCore = (Get-Module -Name CIPPCore).ModuleBase
    $CIPPRoot = (Get-Item -Path $CIPPCore).Parent.Parent.FullName

    $CippRolesJson = Join-Path -Path $CIPPRoot -ChildPath 'Config\cipp-roles.json'
    if (Test-Path $CippRolesJson) {
        $DefaultRoles = Get-Content -Path $CippRolesJson | ConvertFrom-Json
    } else {
        throw "Could not find $CippRolesJson"
    }

    $BlockedRoles = @('anonymous', 'authenticated')

    if ($Request.Body.RoleName -in $BlockedRoles) {
        throw "Role name $($Request.Body.RoleName) cannot be used"
    }

    switch ($Action) {
        'AddUpdate' {
            try {
                $Results = [System.Collections.Generic.List[string]]::new()
                Write-LogMessage -headers $Request.Headers -API 'ExecCustomRole' -message "Saved custom role $($Request.Body.RoleName)" -Sev 'Info'

                # Process IP Range if provided (but not for superadmin to prevent lockout)
                if ($Request.Body.IpRange -and $Request.Body.RoleName -ne 'superadmin') {
                    $IpRange = [System.Collections.Generic.List[string]]::new()
                    $regexPattern = '^(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/\d{1,2})?|(?:[0-9A-Fa-f]{1,4}:){1,7}[0-9A-Fa-f]{1,4}(?:/\d{1,3})?)$'
                    foreach ($IP in @($Request.Body.IpRange)) {
                        if ($IP -match $regexPattern) {
                            $IpRange.Add($IP)
                        }
                    }
                } else {
                    $IpRange = @()
                }

                if ($Request.Body.RoleName -notin $DefaultRoles.PSObject.Properties.Name) {
                    $Role = @{
                        'PartitionKey'     = 'CustomRoles'
                        'RowKey'           = "$($Request.Body.RoleName.ToLower())"
                        'Permissions'      = "$($Request.Body.Permissions | ConvertTo-Json -Compress)"
                        'AllowedTenants'   = "$($Request.Body.AllowedTenants | ConvertTo-Json -Compress)"
                        'BlockedTenants'   = "$($Request.Body.BlockedTenants | ConvertTo-Json -Compress)"
                        'BlockedEndpoints' = "$($Request.Body.BlockedEndpoints | ConvertTo-Json -Compress)"
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $Role -Force | Out-Null
                    $Results.Add("Custom role $($Request.Body.RoleName) saved")
                }
                if ($Request.Body.RoleName -eq 'superadmin' -and $Request.Body.IpRange) {
                    $Results.Add('Note: IP restrictions are not allowed on the superadmin role to prevent lockout issues.')
                }
                # Store IP ranges in separate table (works for both custom and default roles)
                if ($IpRange.Count -gt 0 -and $Request.Body.RoleName -ne 'superadmin') {
                    $IPRangeEntity = @{
                        'PartitionKey' = 'AccessIPRanges'
                        'RowKey'       = "$($Request.Body.RoleName.ToLower())"
                        'IPRanges'     = "$(@($IpRange) | ConvertTo-Json -Compress)"
                    }
                    Add-CIPPAzDataTableEntity @AccessIPRangeTable -Entity $IPRangeEntity -Force | Out-Null
                    $Results.Add("IP ranges configured for '$($Request.Body.RoleName)' role.")
                } else {
                    # Remove IP ranges if none provided or role is superadmin
                    $ExistingIPRange = Get-CIPPAzDataTableEntity @AccessIPRangeTable -Filter "RowKey eq '$($Request.Body.RoleName.ToLower())'"
                    if ($ExistingIPRange) {
                        Remove-AzDataTableEntity -Force @AccessIPRangeTable -Entity $ExistingIPRange
                        if ($Request.Body.RoleName -ne 'superadmin') {
                            $Results.Add("IP ranges removed from '$($Request.Body.RoleName)' role.")
                        }
                    }
                }
                if ($Request.Body.EntraGroup) {
                    $RoleGroup = @{
                        'PartitionKey' = 'AccessRoleGroups'
                        'RowKey'       = "$($Request.Body.RoleName.ToLower())"
                        'GroupId'      = $Request.Body.EntraGroup.value
                        'GroupName'    = $Request.Body.EntraGroup.label
                    }
                    Add-CIPPAzDataTableEntity @AccessRoleGroupTable -Entity $RoleGroup -Force | Out-Null
                    $Results.Add("Security group '$($Request.Body.EntraGroup.label)' assigned to the '$($Request.Body.RoleName)' role.")
                    Write-LogMessage -headers $Request.Headers -API 'ExecCustomRole' -message "Security group '$($Request.Body.EntraGroup.label)' assigned to the '$($Request.Body.RoleName)' role." -Sev 'Info'
                } else {
                    $AccessRoleGroup = Get-CIPPAzDataTableEntity @AccessRoleGroupTable -Filter "RowKey eq '$($Request.Body.RoleName)'"
                    if ($AccessRoleGroup) {
                        Remove-AzDataTableEntity -Force @AccessRoleGroupTable -Entity $AccessRoleGroup
                        $Results.Add("Security group '$($AccessRoleGroup.GroupName)' removed from the '$($Request.Body.RoleName)' role.")
                        Write-LogMessage -headers $Request.Headers -API 'ExecCustomRole' -message "Security group '$($AccessRoleGroup.GroupName)' removed from the '$($Request.Body.RoleName)' role." -Sev 'Info'
                    }
                }
                $Body = @{Results = $Results }
            } catch {
                Write-Warning "Failed to save custom role $($Request.Body.RoleName): $($_.Exception.Message)"
                Write-Warning $_.InvocationInfo.PositionMessage
                $Body = @{Results = "Failed to save custom role $($Request.Body.RoleName)" }
            }
        }
        'Clone' {
            try {
                if ($Request.Body.NewRoleName -in $DefaultRoles.PSObject.Properties.Name) {
                    throw "Role name $($Request.Body.NewRoleName) cannot be used"
                }
                $ExistingRole = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.RoleName.ToLower())'"
                if (!$ExistingRole) {
                    throw "Role $($Request.Body.RoleName) not found"
                }

                if ($ExistingRole.RowKey -eq $Request.Body.NewRoleName.ToLower()) {
                    throw 'New role name cannot be the same as the existing role name'
                }

                $NewRoleTest = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.NewRoleName.ToLower())'"
                if ($NewRoleTest) {
                    throw "Role name $($Request.Body.NewRoleName) already exists"
                }

                $NewRole = @{
                    'PartitionKey'     = 'CustomRoles'
                    'RowKey'           = "$($Request.Body.NewRoleName.ToLower())"
                    'Permissions'      = $ExistingRole.Permissions
                    'AllowedTenants'   = $ExistingRole.AllowedTenants
                    'BlockedTenants'   = $ExistingRole.BlockedTenants
                    'BlockedEndpoints' = $ExistingRole.BlockedEndpoints
                }
                Add-CIPPAzDataTableEntity @Table -Entity $NewRole -Force | Out-Null
                # Clone IP ranges if they exist
                $ExistingIPRange = Get-CIPPAzDataTableEntity @AccessIPRangeTable -Filter "RowKey eq '$($Request.Body.RoleName.ToLower())'"
                if ($ExistingIPRange) {
                    $NewIPRangeEntity = @{
                        'PartitionKey' = 'AccessIPRanges'
                        'RowKey'       = "$($Request.Body.NewRoleName.ToLower())"
                        'IPRanges'     = $ExistingIPRange.IPRanges
                    }
                    Add-CIPPAzDataTableEntity @AccessIPRangeTable -Entity $NewIPRangeEntity -Force | Out-Null
                }
                $Body = @{Results = "Custom role '$($Request.Body.NewRoleName)' cloned from '$($Request.Body.RoleName)'" }
                Write-LogMessage -headers $Request.Headers -API 'ExecCustomRole' -message "Cloned custom role $($Request.Body.RoleName) to $($Request.Body.NewRoleName)" -Sev 'Info'
            } catch {
                Write-Warning "Failed to clone custom role $($Request.Body.RoleName): $($_.Exception.Message)"
                Write-Warning $_.InvocationInfo.PositionMessage
                $Body = @{Results = "Failed to clone custom role $($Request.Body.RoleName)" }
            }
        }
        'Delete' {
            Write-Information "Deleting custom role $($Request.Body.RoleName)"
            $Role = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.RoleName)'" -Property RowKey, PartitionKey
            Remove-AzDataTableEntity -Force @Table -Entity $Role
            $AccessRoleGroup = Get-CIPPAzDataTableEntity @AccessRoleGroupTable -Filter "PartitionKey eq 'AccessRoleGroups' and RowKey eq '$($Request.Body.RoleName)'"
            if ($AccessRoleGroup) {
                Remove-AzDataTableEntity -Force @AccessRoleGroupTable -Entity $AccessRoleGroup
            }
            $AccessIPRange = Get-CIPPAzDataTableEntity @AccessIPRangeTable -Filter "PartitionKey eq 'AccessIPRanges' and RowKey eq '$($Request.Body.RoleName)'"
            if ($AccessIPRange) {
                Remove-AzDataTableEntity -Force @AccessIPRangeTable -Entity $AccessIPRange
            }
            $Body = @{Results = 'Custom role deleted' }
            Write-LogMessage -headers $Request.Headers -API 'ExecCustomRole' -message "Deleted custom role $($Request.Body.RoleName)" -Sev 'Info'
        }
        'ListEntraGroups' {
            $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$filter=securityEnabled eq true' -tenantid $env:TenantID -NoAuthCheck $true
            $Body = @{
                Results  = @($Groups)
                Metadata = @{
                    GroupCount = $Groups.Count
                }
            }
        }
        default {
            $Body = Get-CIPPAzDataTableEntity @Table
            $EntraRoleGroups = Get-CIPPAzDataTableEntity @AccessRoleGroupTable
            $AccessIPRanges = Get-CIPPAzDataTableEntity @AccessIPRangeTable
            if (!$Body) {
                $Body = @(
                    @{
                        RowKey = 'No custom roles found'
                    }
                )
            } else {
                $CustomRoles = foreach ($Role in $Body) {
                    try {
                        $Role.Permissions = $Role.Permissions | ConvertFrom-Json
                    } catch {
                        $Role.Permissions = @()
                    }
                    if ($Role.AllowedTenants) {
                        try {
                            $Role.AllowedTenants = @($Role.AllowedTenants | ConvertFrom-Json)
                        } catch {
                            $Role.AllowedTenants = @()
                        }
                    } else {
                        $Role | Add-Member -NotePropertyName AllowedTenants -NotePropertyValue @() -Force
                    }
                    if ($Role.BlockedTenants) {
                        try {
                            $Role.BlockedTenants = @($Role.BlockedTenants | ConvertFrom-Json)
                        } catch {
                            $Role.BlockedTenants = @()
                        }
                    } else {
                        $Role | Add-Member -NotePropertyName BlockedTenants -NotePropertyValue @() -Force
                    }
                    if ($Role.BlockedEndpoints) {
                        try {
                            $Role.BlockedEndpoints = @($Role.BlockedEndpoints | ConvertFrom-Json)
                        } catch {
                            $Role.BlockedEndpoints = @()
                        }
                    } else {
                        $Role | Add-Member -NotePropertyName BlockedEndpoints -NotePropertyValue @() -Force
                    }
                    $EntraRoleGroup = $EntraRoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey
                    if ($EntraRoleGroup) {
                        $EntraGroup = $EntraRoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey | Select-Object @{Name = 'label'; Expression = { $_.GroupName } }, @{Name = 'value'; Expression = { $_.GroupId } }

                        $Role | Add-Member -NotePropertyName EntraGroup -NotePropertyValue $EntraGroup -Force
                    }
                    # Load IP ranges from separate table
                    $IPRangeEntity = $AccessIPRanges | Where-Object -Property RowKey -EQ $Role.RowKey
                    if ($IPRangeEntity) {
                        try {
                            $IPRanges = @($IPRangeEntity.IPRanges | ConvertFrom-Json)
                        } catch {
                            $IPRanges = @()
                        }
                        $Role | Add-Member -NotePropertyName IPRange -NotePropertyValue $IPRanges -Force
                    } else {
                        $Role | Add-Member -NotePropertyName IPRange -NotePropertyValue @() -Force
                    }
                    $Role
                }
                $DefaultRoles = foreach ($DefaultRole in $DefaultRoles.PSObject.Properties.Name) {
                    $Role = @{
                        RowKey           = $DefaultRole
                        Permissions      = $DefaultRoles.$DefaultRole
                        AllowedTenants   = @('AllTenants')
                        BlockedTenants   = @()
                        BlockedEndpoints = @()
                    }
                    $EntraRoleGroup = $EntraRoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey
                    if ($EntraRoleGroup) {
                        $Role.EntraGroup = $EntraRoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey | Select-Object @{Name = 'label'; Expression = { $_.GroupName } }, @{Name = 'value'; Expression = { $_.GroupId } }
                    }
                    # Load IP ranges from separate table
                    $IPRangeEntity = $AccessIPRanges | Where-Object -Property RowKey -EQ $DefaultRole
                    if ($IPRangeEntity) {
                        try {
                            $IPRanges = @($IPRangeEntity.IPRanges | ConvertFrom-Json)
                        } catch {
                            $IPRanges = @()
                        }
                        $Role.IPRange = $IPRanges
                    } else {
                        $Role.IPRange = @()
                    }
                    $Role
                }
                $Body = @($DefaultRoles + $CustomRoles)
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
