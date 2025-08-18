function Get-CippAllowedPermissions {
    <#
    .SYNOPSIS
        Retrieves the allowed permissions for the current user.

    .DESCRIPTION
        This function retrieves the allowed permissions for the current user based on their role and the configured permissions in the CIPP system.
        For admin/superadmin users, permissions are computed from base role include/exclude rules.
        For editor/readonly users, permissions start from base role and are restricted by custom roles.

    .PARAMETER UserRoles
        Array of user roles to compute permissions for.

    .OUTPUTS
        Returns a list of allowed permissions for the current user.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$UserRoles
    )

    # Get all available permissions and base roles configuration

    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $Version = (Get-Content -Path $CIPPRoot\version_latest.txt).trim()
    $BaseRoles = Get-Content -Path $CIPPRoot\Config\cipp-roles.json | ConvertFrom-Json
    $DefaultRoles = @('superadmin', 'admin', 'editor', 'readonly', 'anonymous', 'authenticated')

    $AllPermissionCacheTable = Get-CIPPTable -tablename 'cachehttppermissions'
    $AllPermissionsRow = Get-CIPPAzDataTableEntity @AllPermissionCacheTable -Filter "PartitionKey eq 'HttpFunctions' and RowKey eq 'HttpFunctions' and Version eq '$($Version)'"

    if (-not $AllPermissionsRow) {
        $AllPermissions = Get-CIPPHttpFunctions -ByRole | Select-Object -ExpandProperty Permission
        $Entity = @{
            PartitionKey = 'HttpFunctions'
            RowKey       = 'HttpFunctions'
            Version      = [string]$Version
            Permissions  = [string]($AllPermissions | ConvertTo-Json -Compress)
        }
        Add-CIPPAzDataTableEntity @AllPermissionCacheTable -Entity $Entity -Force
    } else {
        $AllPermissions = $AllPermissionsRow.Permissions | ConvertFrom-Json
    }

    $AllowedPermissions = [System.Collections.Generic.List[string]]::new()

    # Determine user's primary base role (highest priority first)
    $BaseRole = $null
    $PrimaryRole = $null

    if ($UserRoles -contains 'superadmin') {
        $PrimaryRole = 'superadmin'
    } elseif ($UserRoles -contains 'admin') {
        $PrimaryRole = 'admin'
    } elseif ($UserRoles -contains 'editor') {
        $PrimaryRole = 'editor'
    } elseif ($UserRoles -contains 'readonly') {
        $PrimaryRole = 'readonly'
    }

    if ($PrimaryRole) {
        $BaseRole = $BaseRoles.PSObject.Properties | Where-Object { $_.Name -eq $PrimaryRole } | Select-Object -First 1
    }

    # Get custom roles (non-default roles)
    $CustomRoles = $UserRoles | Where-Object { $DefaultRoles -notcontains $_ }

    # For admin and superadmin: Compute permissions from base role include/exclude rules
    if ($PrimaryRole -in @('admin', 'superadmin')) {

        if ($BaseRole) {
            # Start with all permissions and apply include/exclude rules
            $BasePermissions = [System.Collections.Generic.List[string]]::new()

            # Apply include rules
            foreach ($Include in $BaseRole.Value.include) {
                $MatchingPermissions = $AllPermissions | Where-Object { $_ -like $Include }
                foreach ($Permission in $MatchingPermissions) {
                    if ($BasePermissions -notcontains $Permission) {
                        $BasePermissions.Add($Permission)
                    }
                }
            }

            # Apply exclude rules
            foreach ($Exclude in $BaseRole.Value.exclude) {
                $ExcludedPermissions = $BasePermissions | Where-Object { $_ -like $Exclude }
                foreach ($Permission in $ExcludedPermissions) {
                    $BasePermissions.Remove($Permission) | Out-Null
                }
            }

            foreach ($Permission in $BasePermissions) {
                $AllowedPermissions.Add($Permission)
            }
        }
    }
    # For editor and readonly: Start with base role permissions and restrict with custom roles
    elseif ($PrimaryRole -in @('editor', 'readonly')) {
        Write-Information "Computing permissions for $PrimaryRole with custom role restrictions"

        if ($BaseRole) {
            # Get base role permissions first
            $BasePermissions = [System.Collections.Generic.List[string]]::new()

            # Apply include rules from base role
            foreach ($Include in $BaseRole.Value.include) {
                $MatchingPermissions = $AllPermissions | Where-Object { $_ -like $Include }
                foreach ($Permission in $MatchingPermissions) {
                    if ($BasePermissions -notcontains $Permission) {
                        $BasePermissions.Add($Permission)
                    }
                }
            }

            # Apply exclude rules from base role
            foreach ($Exclude in $BaseRole.Value.exclude) {
                $ExcludedPermissions = $BasePermissions | Where-Object { $_ -like $Exclude }
                foreach ($Permission in $ExcludedPermissions) {
                    $BasePermissions.Remove($Permission) | Out-Null
                }
            }

            # If custom roles exist, intersect with custom role permissions (restriction)
            if ($CustomRoles.Count -gt 0) {
                $CustomRolePermissions = [System.Collections.Generic.List[string]]::new()

                foreach ($CustomRole in $CustomRoles) {
                    try {
                        $RolePermissions = Get-CIPPRolePermissions -RoleName $CustomRole
                        foreach ($Permission in $RolePermissions.Permissions) {
                            if ($null -ne $Permission -and $Permission -is [string] -and $CustomRolePermissions -notcontains $Permission) {
                                $CustomRolePermissions.Add($Permission)
                            }
                        }
                    } catch {
                        Write-Warning "Failed to get permissions for custom role '$CustomRole': $($_.Exception.Message)"
                    }
                }

                # Restrict base permissions to only those allowed by custom roles
                # Include Read permissions when ReadWrite permissions are present
                $RestrictedPermissions = $BasePermissions | Where-Object {
                    $Permission = $_
                    if ($CustomRolePermissions -contains $Permission) {
                        $true
                    } elseif ($Permission -match 'Read$') {
                        # Check if there's a corresponding ReadWrite permission
                        $ReadWritePermission = $Permission -replace 'Read', 'ReadWrite'
                        $CustomRolePermissions -contains $ReadWritePermission
                    } else {
                        $false
                    }
                }
                foreach ($Permission in $RestrictedPermissions) {
                    if ($null -ne $Permission -and $Permission -is [string]) {
                        $AllowedPermissions.Add($Permission)
                    }
                }
            } else {
                # No custom roles, use base role permissions
                foreach ($Permission in $BasePermissions) {
                    if ($null -ne $Permission -and $Permission -is [string]) {
                        $AllowedPermissions.Add($Permission)
                    }
                }
            }
        }
    }
    # Handle users with only custom roles (no base role)
    elseif ($CustomRoles.Count -gt 0) {
        foreach ($CustomRole in $CustomRoles) {
            try {
                $RolePermissions = Get-CIPPRolePermissions -RoleName $CustomRole
                foreach ($Permission in $RolePermissions.Permissions) {
                    if ($null -ne $Permission -and $Permission -is [string] -and $AllowedPermissions -notcontains $Permission) {
                        $AllowedPermissions.Add($Permission)
                    }
                }
            } catch {
                Write-Warning "Failed to get permissions for custom role '$CustomRole': $($_.Exception.Message)"
            }
        }
    }

    # Return sorted unique permissions
    return ($AllowedPermissions | Sort-Object -Unique)
}
