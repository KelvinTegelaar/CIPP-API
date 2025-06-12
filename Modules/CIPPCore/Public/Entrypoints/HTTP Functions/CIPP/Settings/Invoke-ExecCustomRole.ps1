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
    $Action = $Request.Query.Action ?? $Request.Body.Action

    $DefaultRoles = @('readonly', 'editor', 'admin', 'superadmin')
    $BlockedRoles = @('anonymous', 'authenticated')

    if ($Request.Body.RoleName -in $BlockedRoles) {
        throw "Role name $($Request.Body.RoleName) cannot be used"
    }

    switch ($Action) {
        'AddUpdate' {
            try {
                $Results = [System.Collections.Generic.List[string]]::new()
                Write-LogMessage -headers $Request.Headers -API 'ExecCustomRole' -message "Saved custom role $($Request.Body.RoleName)" -Sev 'Info'
                if ($Request.Body.RoleName -notin $DefaultRoles) {
                    $Role = @{
                        'PartitionKey'   = 'CustomRoles'
                        'RowKey'         = "$($Request.Body.RoleName.ToLower())"
                        'Permissions'    = "$($Request.Body.Permissions | ConvertTo-Json -Compress)"
                        'AllowedTenants' = "$($Request.Body.AllowedTenants | ConvertTo-Json -Compress)"
                        'BlockedTenants' = "$($Request.Body.BlockedTenants | ConvertTo-Json -Compress)"
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $Role -Force | Out-Null
                    $Results.Add("Custom role $($Request.Body.RoleName) saved")
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
        'Delete' {
            Write-Information "Deleting custom role $($Request.Body.RoleName)"
            $Role = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.RoleName)'" -Property RowKey, PartitionKey
            Remove-AzDataTableEntity -Force @Table -Entity $Role
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
                        $Role.Permissions = ''
                    }
                    if ($Role.AllowedTenants) {
                        try {
                            $Role.AllowedTenants = @($Role.AllowedTenants | ConvertFrom-Json)
                        } catch {
                            $Role.AllowedTenants = ''
                        }
                    } else {
                        $Role | Add-Member -NotePropertyName AllowedTenants -NotePropertyValue @() -Force
                    }
                    if ($Role.BlockedTenants) {
                        try {
                            $Role.BlockedTenants = @($Role.BlockedTenants | ConvertFrom-Json)
                        } catch {
                            $Role.BlockedTenants = ''
                        }
                    } else {
                        $Role | Add-Member -NotePropertyName BlockedTenants -NotePropertyValue @() -Force
                    }
                    $EntraRoleGroup = $EntraRoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey
                    if ($EntraRoleGroup) {
                        $EntraGroup = $EntraRoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey | Select-Object @{Name = 'label'; Expression = { $_.GroupName } }, @{Name = 'value'; Expression = { $_.GroupId } }

                        $Role | Add-Member -NotePropertyName EntraGroup -NotePropertyValue $EntraGroup -Force
                    }
                    $Role
                }
                $DefaultRoles = foreach ($DefaultRole in $DefaultRoles) {
                    $Role = @{
                        RowKey         = $DefaultRole
                        Permissions    = ''
                        AllowedTenants = @('AllTenants')
                        BlockedTenants = @('')
                    }
                    $EntraRoleGroup = $EntraRoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey
                    if ($EntraRoleGroup) {
                        $Role.EntraGroup = $EntraRoleGroups | Where-Object -Property RowKey -EQ $Role.RowKey | Select-Object @{Name = 'label'; Expression = { $_.GroupName } }, @{Name = 'value'; Expression = { $_.GroupId } }
                    }
                    $Role
                }
                $Body = @($DefaultRoles + $CustomRoles)
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
