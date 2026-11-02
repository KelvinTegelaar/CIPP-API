function Get-CIPPJITAdminAllowedRoles {
    <#
    .SYNOPSIS
    Resolve which directory roles the calling user is permitted to assign via JIT Admin.

    .DESCRIPTION
    JIT Role Templates are named allow-lists of Entra directory roles that can be attached to a
    CIPP custom role (via the AllowedRolesTemplate property on the CustomRoles row). This function
    resolves the calling user's roles and returns the effective allow-list.

    Restrictive semantics, matching how CIPP combines multiple custom roles everywhere else
    ("assigning multiple custom roles is restrictive and not additive"):
      - Base roles (superadmin/admin/editor/readonly) do not carry templates. admin/superadmin are
        unaffected by custom roles and are always unrestricted.
      - A custom role with NO template contributes "all roles" (the universal set), so it never
        loosens the result - but on its own it does not restrict.
      - If the caller holds AT LEAST ONE templated custom role they are restricted, and the allow-list
        is the INTERSECTION of the templated roles' sets. An untemplated custom role therefore cannot
        be used to bypass a template held alongside it.
      - If NO custom role carries a template, the caller is unrestricted, so deployments with no
        templates assigned anywhere are undisturbed.

    Fails closed for restricted callers: a template (or role row) that cannot be read contributes an
    empty set to the intersection rather than opening access, so a lookup failure cannot escalate.

    .PARAMETER Headers
    The request headers (containing x-ms-client-principal) used to resolve the caller.

    .OUTPUTS
    PSCustomObject with:
      Restricted     [bool]    - $true when the allow-list should be enforced.
      AllowedRoleIds [string[]] - directory role template IDs the caller may assign (only meaningful when Restricted).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Headers
    )

    $Unrestricted = [PSCustomObject]@{ Restricted = $false; AllowedRoleIds = @() }

    # Resolve the calling user's roles, including Entra group-based roles (mirrors Invoke-ExecRestoreBackup)
    try {
        $CallingUser = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json
    } catch {
        # Without a resolvable principal we cannot determine a custom role, so nothing is restricted.
        return $Unrestricted
    }

    if (($CallingUser.userRoles | Measure-Object).Count -eq 2 -and $CallingUser.userRoles -contains 'authenticated' -and $CallingUser.userRoles -contains 'anonymous') {
        $CallingUser = Test-CIPPAccessUserRole -User $CallingUser
    }

    # admin/superadmin are unaffected by custom roles (CIPP convention) -> never restricted.
    if ($CallingUser.userRoles -contains 'admin' -or $CallingUser.userRoles -contains 'superadmin') {
        return $Unrestricted
    }

    $DefaultRoles = @('superadmin', 'admin', 'editor', 'readonly', 'anonymous', 'authenticated')
    $CustomRoleNames = @($CallingUser.userRoles | Where-Object { $DefaultRoles -notcontains $_ })

    # No custom role -> unrestricted (base roles have no template concept).
    if ($CustomRoleNames.Count -eq 0) {
        return $Unrestricted
    }

    $Table = Get-CIPPTable -tablename 'CustomRoles'
    $TemplateTable = Get-CIPPTable -tablename 'templates'

    # Each templated custom role contributes one set of allowed role IDs. Untemplated custom roles
    # contribute nothing (they represent the universal set and never tighten the intersection).
    $TemplatedSets = [System.Collections.Generic.List[object]]::new()

    foreach ($RoleName in $CustomRoleNames) {
        try {
            $SafeRole = ConvertTo-CIPPODataFilterValue -Value ($RoleName.ToLower()) -Type String
            $RoleRow = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CustomRoles' and RowKey eq '$SafeRole'"
        } catch {
            Write-Warning "JIT allowed-roles: failed to read custom role '$RoleName': $($_.Exception.Message)"
            # Cannot confirm whether this role is templated -> fail closed: contribute an empty set.
            $TemplatedSets.Add([string[]]@())
            continue
        }

        # A role with no template assigned represents the universal set - skip it (it never restricts).
        if (-not $RoleRow -or [string]::IsNullOrWhiteSpace($RoleRow.AllowedRolesTemplate)) {
            continue
        }

        try {
            $TemplateRef = $RoleRow.AllowedRolesTemplate | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $TemplateRef = $RoleRow.AllowedRolesTemplate
        }
        $TemplateGuid = if ($TemplateRef -is [string]) { $TemplateRef } else { $TemplateRef.value ?? $TemplateRef.GUID }

        # A blank template reference is equivalent to no template -> universal set, skip it.
        if ([string]::IsNullOrWhiteSpace($TemplateGuid)) {
            continue
        }

        try {
            $SafeGuid = ConvertTo-CIPPODataFilterValue -Value $TemplateGuid -Type Guid
            $TemplateRow = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'JITRoleTemplate' and RowKey eq '$SafeGuid'"
        } catch {
            Write-Warning "JIT allowed-roles: failed to read JIT Role Template '$TemplateGuid': $($_.Exception.Message)"
            $TemplateRow = $null
        }

        # A templated role whose template cannot be resolved contributes an empty set (fail closed).
        if (-not $TemplateRow) {
            $TemplatedSets.Add([string[]]@())
            continue
        }

        try {
            $TemplateData = $TemplateRow.JSON | ConvertFrom-Json -Depth 10 -ErrorAction Stop
        } catch {
            $TemplatedSets.Add([string[]]@())
            continue
        }
        $Ids = foreach ($Role in @($TemplateData.roles)) {
            $Id = if ($Role -is [string]) { $Role } else { $Role.value ?? $Role.ObjectId }
            if (-not [string]::IsNullOrWhiteSpace($Id)) { [string]$Id }
        }
        $TemplatedSets.Add([string[]]@($Ids))
    }

    # No templated custom role -> nothing restricts the caller.
    if ($TemplatedSets.Count -eq 0) {
        return $Unrestricted
    }

    # Restricted: the allow-list is the intersection of every templated role's set (most restrictive wins).
    $Intersection = $null
    foreach ($Set in $TemplatedSets) {
        if ($null -eq $Intersection) {
            $Intersection = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Set))
        } else {
            $Intersection.IntersectWith([string[]]@($Set))
        }
    }

    return [PSCustomObject]@{
        Restricted     = $true
        AllowedRoleIds = @($Intersection)
    }
}
