function Invoke-ListCustomRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $DefaultRoles = @('readonly', 'editor', 'admin', 'superadmin')
    $Table = Get-CippTable -tablename 'CustomRoles'
    $CustomRoles = Get-CIPPAzDataTableEntity @Table

    $AccessRoleGroupTable = Get-CippTable -tablename 'AccessRoleGroups'
    $RoleGroups = Get-CIPPAzDataTableEntity @AccessRoleGroupTable

    $TenantList = Get-Tenants -IncludeErrors

    $RoleList = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($Role in $DefaultRoles) {
        $RoleGroup = $RoleGroups | Where-Object -Property RowKey -EQ $Role

        $RoleList.Add([pscustomobject]@{
                RoleName       = $Role
                Type           = 'Built-In'
                Permissions    = ''
                AllowedTenants = @('AllTenants')
                BlockedTenants = @()
                EntraGroup     = $RoleGroup.GroupName ?? $null
                EntraGroupId   = $RoleGroup.GroupId ?? $null
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
            try {
                $AllowedTenants = $Role.AllowedTenants | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
                    $TenantId = $_
                    $TenantList | Where-Object { $_.customerId -eq $TenantId } | Select-Object -ExpandProperty defaultDomainName
                }
                $AllowedTenants = $AllowedTenants ?? @('AllTenants')
                $Role.AllowedTenants = @($AllowedTenants)
            } catch {
                $Role.AllowedTenants = @('AllTenants')
            }
        } else {
            $Role | Add-Member -NotePropertyName AllowedTenants -NotePropertyValue @() -Force
        }
        if ($Role.BlockedTenants) {
            try {
                $BlockedTenants = $Role.BlockedTenants | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
                    $TenantId = $_
                    $TenantList | Where-Object { $_.customerId -eq $TenantId } | Select-Object -ExpandProperty defaultDomainName
                }
                $BlockedTenants = $BlockedTenants ?? @()
                $Role.BlockedTenants = @($BlockedTenants)
            } catch {
                $Role.BlockedTenants = @()
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

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -InputObject $Body -Depth 5
        })
}
