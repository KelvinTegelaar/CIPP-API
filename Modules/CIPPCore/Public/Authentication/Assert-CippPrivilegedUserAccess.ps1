function Assert-CippPrivilegedUserAccess {
    <#
    .SYNOPSIS
        Throws UnauthorizedAccessException when the caller lacks Identity.PrivilegedUser.ReadWrite and a target user holds a privileged Entra role.
    .DESCRIPTION
        Guards the actions Microsoft treats as sensitive on privileged users (password and authentication method
        changes, disable, delete and restore, session revocation, sensitive properties). Callers holding the permission,
        and work running outside a request, skip the Graph lookup unless -Enforce or a restricted scheduled task (one
        queued by a caller without the permission) requires the check.

        A user counts as privileged when a built-in role Entra flags isPrivileged, active at any scope or PIM eligible,
        is held by the user, by a group the user is a member or owner of, or by a group the user is PIM eligible to
        join or own. In a partner tenant, membership or ownership of AdminAgents, HelpdeskAgents or a GDAP group in
        the GDAPRoles table also counts, because those grant admin roles in customer tenants. Anything that cannot be
        checked fails the request rather than letting it through.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        # Object ids or UPNs of the users the action targets (object ids only with -Deleted)
        [string[]]$UserId,
        [switch]$Enforce,
        # The targets are in deleted items, so only the roles they held themselves can be read
        [switch]$Deleted,
        # Return the privileged targets instead of refusing, so a bulk action can skip them and do the rest
        [switch]$PassThru
    )

    $RestrictedTask = $script:CippPrivilegedUserRestrictedStorage -and $script:CippPrivilegedUserRestrictedStorage.Value
    if (-not $Enforce -and -not $RestrictedTask) {
        $Allowed = Get-CippRequestAllowedPermissions
        if ($null -eq $Allowed -or $Allowed -contains 'Identity.PrivilegedUser.ReadWrite') { return }
    }
    $UserIds = @([System.Collections.Generic.HashSet[string]]::new([string[]]@($UserId.Where({ -not [string]::IsNullOrWhiteSpace($_) })), [System.StringComparer]::OrdinalIgnoreCase))
    if ($UserIds.Count -eq 0) { return }

    # Who holds a privileged role is read once a minute per tenant, so a bulk run of per-user requests does not
    # re-read the tenant; each user's own memberships are always read live.
    if (-not $script:CippPrivilegedPrincipalMemo) { $script:CippPrivilegedPrincipalMemo = @{} }
    $Now = [datetime]::UtcNow
    $Memo = $script:CippPrivilegedPrincipalMemo[$TenantFilter]
    if ($Memo -and $Memo.Expires -lt $Now) { $Memo = $null }

    $Requests = [System.Collections.Generic.List[hashtable]]::new()
    if (-not $Memo) {
        $PIMCapable = [bool](Test-CIPPStandardLicense -StandardName 'PIMRoleAssignments' -TenantFilter $TenantFilter -Preset PIM -SkipLog)
        $Requests.Add(@{ id = 'active'; method = 'GET'; url = 'roleManagement/directory/roleAssignments?$select=principalId,roleDefinitionId' })
        if ($PIMCapable) {
            $Requests.Add(@{ id = 'eligible'; method = 'GET'; url = 'roleManagement/directory/roleEligibilitySchedules?$select=principalId,roleDefinitionId' })
        }
        $Requests.Add(@{ id = 'org'; method = 'GET'; url = 'organization?$select=id' })
    }
    if (-not $Deleted) {
        for ($i = 0; $i -lt $UserIds.Count; $i++) {
            # A guest UPN carries #EXT#, which unescaped ends the path.
            $UserPath = "users/$([uri]::EscapeDataString($UserIds[$i]))"
            $Requests.Add(@{ id = "user-$i"; method = 'GET'; url = "$UserPath`?`$select=id" })
            $Requests.Add(@{ id = "member-$i"; method = 'GET'; url = "$UserPath/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName" })
            $Requests.Add(@{ id = "owner-$i"; method = 'GET'; url = "$UserPath/ownedObjects/microsoft.graph.group?`$select=id,displayName" })
        }
    }
    $Responses = @{}
    if ($Requests.Count -gt 0) {
        foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -asapp $true -Version 'v1.0')) {
            $Responses[[string]$Response.id] = $Response
        }
    }
    $Failed = { param($Id) $null -eq $Responses[$Id] -or [int]$Responses[$Id].status -ge 400 -or $Responses[$Id].PagingIncomplete }

    if (-not $Memo) {
        foreach ($Id in @($Requests.id).Where({ $_ -in 'active', 'eligible' })) {
            if (& $Failed $Id) { throw "Could not read the $Id role assignments in $TenantFilter to check for privileged users: $($Responses[$Id].body.error.message)" }
        }
        if (& $Failed 'org') { throw "Could not read the tenant id of $TenantFilter to check for privileged users: $($Responses['org'].body.error.message)" }

        $PrivilegedRoles = [System.Collections.Generic.HashSet[string]]::new([string[]]@(Get-CIPPPrivilegedRoleTemplateIds -Set EntraPrivileged), [System.StringComparer]::OrdinalIgnoreCase)
        $Principals = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Assignment in @($Responses['active'].body.value) + @($Responses['eligible'].body.value)) {
            if ($Assignment.principalId -and $PrivilegedRoles.Contains([string]$Assignment.roleDefinitionId)) { $null = $Principals.Add([string]$Assignment.principalId) }
        }
        $OrgId = [string]@($Responses['org'].body.value)[0].id
        $IsPartner = [bool]($OrgId -and ($OrgId -eq $env:TenantID -or @(Get-CIPPPartnerTenant -PartnerTenantId $OrgId -IncludeDisabled).Count -gt 0))
        if ($IsPartner) {
            $GdapRolesTable = Get-CIPPTable -TableName 'GDAPRoles'
            foreach ($Mapping in @(Get-CIPPAzDataTableEntity @GdapRolesTable -Filter "PartitionKey eq 'Roles'")) {
                if ($Mapping.GroupId) { $null = $Principals.Add([string]$Mapping.GroupId) }
            }
        }

        $Memo = @{ Expires = $Now.AddSeconds(60); Principals = $Principals; PIMCapable = $PIMCapable; IsPartner = $IsPartner }
        foreach ($Key in @($script:CippPrivilegedPrincipalMemo.Keys)) {
            if ($script:CippPrivilegedPrincipalMemo[$Key].Expires -lt $Now) { $script:CippPrivilegedPrincipalMemo.Remove($Key) }
        }
        $script:CippPrivilegedPrincipalMemo[$TenantFilter] = $Memo
    }
    $PrivilegedPrincipals = $Memo.Principals

    $Privileged = [System.Collections.Generic.List[string]]::new()
    if ($Deleted) {
        foreach ($Target in $UserIds) { if ($PrivilegedPrincipals.Contains($Target)) { $Privileged.Add($Target) } }
    } else {
        $ObjectIds = @{}
        for ($i = 0; $i -lt $UserIds.Count; $i++) {
            $Target = $UserIds[$i]
            foreach ($Id in "user-$i", "member-$i", "owner-$i") {
                if (& $Failed $Id) { throw "Could not check whether $Target holds a privileged role: $($Responses[$Id].body.error.message)" }
            }
            $ObjectIds[$Target] = [string]$Responses["user-$i"].body.id
            $Groups = @(@($Responses["member-$i"].body.value) + @($Responses["owner-$i"].body.value)).Where({ $_ })
            $Candidates = @($ObjectIds[$Target]) + @($Groups.id)
            $PartnerAgent = $Memo.IsPartner -and $Groups.Where({ $_.displayName -in 'AdminAgents', 'HelpdeskAgents' }, 'First').Count -gt 0
            if ($PartnerAgent -or $Candidates.Where({ $_ -and $PrivilegedPrincipals.Contains([string]$_) }, 'First').Count -gt 0) { $Privileged.Add($Target) }
        }

        $Unchecked = @($UserIds.Where({ $Privileged -notcontains $_ }))
        if ($Memo.PIMCapable -and $Unchecked.Count -gt 0) {
            $GroupRequests = for ($i = 0; $i -lt $Unchecked.Count; $i++) {
                @{ id = "$i"; method = 'GET'; url = "identityGovernance/privilegedAccess/group/eligibilitySchedules?`$filter=principalId eq '$($ObjectIds[$Unchecked[$i]])'&`$select=groupId" }
            }
            foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($GroupRequests) -asapp $true -Version 'v1.0')) {
                $Target = $Unchecked[[int]$Response.id]
                if ([int]$Response.status -eq 403) {
                    # PrivilegedEligibilitySchedule.Read.AzureADGroup not consented yet: PIM for Groups cannot be read here.
                    Write-Information "Skipped the PIM for Groups check for $Target in $TenantFilter`: $($Response.body.error.message)"
                    continue
                }
                if ([int]$Response.status -ge 400 -or $Response.PagingIncomplete) { throw "Could not check whether $Target is eligible for a privileged group: $($Response.body.error.message)" }
                if (@($Response.body.value.groupId).Where({ $_ -and $PrivilegedPrincipals.Contains([string]$_) }, 'First').Count -gt 0) { $Privileged.Add($Target) }
            }
        }
    }

    if ($PassThru) { return $Privileged }
    if ($Privileged.Count -gt 0) {
        throw [System.UnauthorizedAccessException]::new("$($Privileged -join ', ') holds a privileged admin role. Managing privileged users needs the Identity.PrivilegedUser.ReadWrite permission.")
    }
}
