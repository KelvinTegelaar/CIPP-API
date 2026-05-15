function Invoke-ListCIPPUsers {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Table = Get-CippTable -tablename 'allowedUsers'

    try {
        # Get all users from the allowedUsers table
        $Users = Get-CIPPAzDataTableEntity @Table | Where-Object { -not $_.RowKey.StartsWith('_') }

        # Get available roles (built-in + custom)
        $CippRolesJson = Join-Path -Path $env:CIPPRootPath -ChildPath 'Config\cipp-roles.json'
        $BuiltInRoles = if (Test-Path $CippRolesJson) {
            ([System.IO.File]::ReadAllText($CippRolesJson) | ConvertFrom-Json).PSObject.Properties.Name
        } else {
            @('readonly', 'editor', 'admin', 'superadmin')
        }

        $CustomRolesTable = Get-CippTable -tablename 'CustomRoles'
        $CustomRoleEntities = Get-CIPPAzDataTableEntity @CustomRolesTable
        $CustomRoleNames = @($CustomRoleEntities | ForEach-Object { $_.RowKey } | Where-Object { $_ })

        # Build user list with parsed roles
        $UserList = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($User in $Users) {
            $ParsedRoles = @()
            if ($User.Roles) {
                try {
                    $ParsedRoles = @($User.Roles | ConvertFrom-Json -ErrorAction Stop)
                } catch {
                    $ParsedRoles = @($User.Roles)
                }
            }

            $UserList.Add([pscustomobject]@{
                UPN   = $User.RowKey
                Roles = $ParsedRoles
            })
        }

        # Build available roles list for frontend dropdown
        $AvailableRoles = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($Role in $BuiltInRoles) {
            $AvailableRoles.Add([pscustomobject]@{
                RoleName = $Role
                Type     = 'Built-In'
            })
        }
        foreach ($Role in $CustomRoleNames) {
            $AvailableRoles.Add([pscustomobject]@{
                RoleName = $Role
                Type     = 'Custom'
            })
        }

        $Body = @{
            Users          = @($UserList)
            AvailableRoles = @($AvailableRoles)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Failed to list CIPP users: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
