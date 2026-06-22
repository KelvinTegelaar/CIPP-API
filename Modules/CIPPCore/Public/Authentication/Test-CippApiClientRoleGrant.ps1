function Test-CippApiClientRoleGrant {
    <#
    .SYNOPSIS
        Validates that the caller of an API client management action is permitted to
        create, modify, reset, or delete an API client holding the supplied role(s).

    .DESCRIPTION
        Prevents privilege escalation through the ApiClients table. The ExecApiClient
        endpoint is gated at CIPP.Extension.ReadWrite (editor-grantable), but the role
        assigned to an API client becomes that client's effective privilege at request
        time (see Test-CIPPAccess). Without this check an editor could mint a client
        with the 'superadmin' role, or reset the secret of an existing superadmin
        client, and escalate.

        A caller may only manage a client whose effective permissions are a subset of
        the caller's own effective permissions. Superadmins may grant any role. Roles
        are compared by computed permission set (built-in and custom), matching exactly
        how Test-CIPPAccess evaluates an API client (single role, no base-role ceiling).

    .PARAMETER Request
        The HTTP request, used to resolve the caller's roles. Handles both interactive
        user principals and API-client principals.

    .PARAMETER Role
        One or more roles to validate, e.g. the requested new role and the existing
        client's current role. An empty/missing role is treated as the runtime
        'cipp-api' fallback that Test-CIPPAccess applies to roleless clients.

    .OUTPUTS
        [pscustomobject] with Allowed [bool] and Message [string]. Fails closed.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Request,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Role
    )

    function New-Denial {
        param([string]$Message)
        [pscustomobject]@{ Allowed = $false; Message = $Message }
    }

    # Resolve the caller's roles. Mirror Test-CIPPAccess's principal detection so this
    # works whether the caller is an interactive user or an API client.
    try {
        if ($Request.Headers.'x-ms-client-principal-idp' -eq 'aad' -and $Request.Headers.'x-ms-client-principal-name' -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            $CallerClient = Get-CippApiClient -AppId $Request.Headers.'x-ms-client-principal-name'
            if ($CallerClient.Role) {
                $CallerRoles = @($CallerClient.Role)
            } else {
                $CallerRoles = @('cipp-api')
            }
        } else {
            $CallerRoles = @(Get-CIPPAccessRole -Request $Request)
        }
    } catch {
        return (New-Denial "Unable to resolve your roles for authorization: $($_.Exception.Message)")
    }

    if (-not $CallerRoles -or $CallerRoles.Count -eq 0) {
        return (New-Denial 'Unable to determine your roles; cannot authorize this API client operation.')
    }

    # Superadmin may grant or manage any role.
    if ($CallerRoles -contains 'superadmin') {
        return [pscustomobject]@{ Allowed = $true; Message = $null }
    }

    $DefaultRoles = @('superadmin', 'admin', 'editor', 'readonly')
    $CallerPermissions = @(Get-CippAllowedPermissions -UserRoles $CallerRoles)

    # Normalize: a roleless client resolves to the 'cipp-api' fallback at request time,
    # so validate against that to mirror real client evaluation and stay future-proof.
    $TargetRoles = @($Role | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { 'cipp-api' } else { $_.Trim() }
        } | Sort-Object -Unique)

    foreach ($TargetRole in $TargetRoles) {
        # anonymous/authenticated are SWA placeholder roles, never valid client roles.
        if (@('anonymous', 'authenticated') -contains $TargetRole) {
            return (New-Denial "The role '$TargetRole' cannot be assigned to an API client.")
        }

        # Confirm the role exists. 'cipp-api' is an implicit runtime fallback and may
        # legitimately not be present in the CustomRoles table, so it is exempt.
        if ($DefaultRoles -notcontains $TargetRole -and $TargetRole -ne 'cipp-api') {
            try {
                $null = Get-CIPPRolePermissions -RoleName $TargetRole
            } catch {
                return (New-Denial "The role '$TargetRole' does not exist.")
            }
        }

        # Effective permissions a client holding this role would receive, computed the
        # same way Test-CIPPAccess evaluates an API client (single role, no base ceiling).
        $RolePermissions = @(Get-CippAllowedPermissions -UserRoles @($TargetRole))
        $Escalation = @($RolePermissions | Where-Object { $CallerPermissions -notcontains $_ })

        if ($Escalation.Count -gt 0) {
            return (New-Denial "You do not have sufficient permissions to manage an API client with the '$TargetRole' role; it grants permissions beyond your own.")
        }
    }

    return [pscustomobject]@{ Allowed = $true; Message = $null }
}
