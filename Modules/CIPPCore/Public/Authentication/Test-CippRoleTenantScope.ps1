function Test-CippRoleTenantScope {
    <#
    .SYNOPSIS
        Whether a custom role's tenant scope covers one target tenant (or tenant group) of a request.

    .DESCRIPTION
        Extracted from the per-endpoint allow path in Test-CIPPAccess. Same rules:
        AllTenants with no blocked list, AllTenants Write/Read request special-cases,
        group targets authorized by group identity, then allowed-minus-blocked after
        expanding tenant groups. Test-CIPPAccess calls it once per tenant the request names.

        An empty tenant filter means the endpoint is not tenant-scoped, so every role
        is in scope. A filter that is present but resolves to no known tenant is
        denied, unless the caller passes -TreatUnresolvedAsInScope — the
        BlockedEndpoints pass does, so its deny still applies to unresolved targets
        (fail closed). Do not fall back to $env:TenantID — that is the partner home
        tenant, not a customer.

    .PARAMETER Role
        Role permission object from Get-CIPPRolePermissions (AllowedTenants, BlockedTenants, ...).

    .PARAMETER TenantFilter
        One target: customerId, domain, AllTenants, or a group ID when -IsGroup is set.

    .PARAMETER Tenants
        Tenant list from Get-Tenants -IncludeErrors (used to resolve filter and expand AllTenants).

    .PARAMETER IsGroup
        The target is a tenant group ID (a {type:'Group'} selector in the request body).

    .PARAMETER TenantSelector
        The group target came from the tenant selector (?tenantGroup), which a role with BlockTenantGroups refuses.

    .PARAMETER ApiRole
        Endpoint permission string; used for AllTenants Write$ / Read$ branches.

    .PARAMETER TreatUnresolvedAsInScope
        Keep a present-but-unresolvable tenant filter in scope instead of denying it, and
        count a group as in scope when the role reaches any of its members. Only the
        BlockedEndpoints pass sets this, so a block always applies (fail closed).

    .OUTPUTS
        [bool] $true if the role's scope covers the target.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        $Role,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        $TenantFilter,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        $Tenants,

        [Parameter()]
        [switch]$IsGroup,

        [Parameter()]
        [switch]$TenantSelector,

        [Parameter(Mandatory = $true)]
        [string]$ApiRole,

        [Parameter()]
        [switch]$TreatUnresolvedAsInScope
    )

    $Tenants = @($Tenants)

    # The flag narrows what a role allows; on the block pass it must not shrink what the role blocks.
    if ($TenantFilter -eq 'AllTenants' -and $Role.BlockAllTenants -and -not $TreatUnresolvedAsInScope) {
        return $false
    }
    if ($IsGroup -and $TenantSelector -and $Role.BlockTenantGroups -and -not $TreatUnresolvedAsInScope) {
        return $false
    }

    if (($Role.BlockedTenants | Measure-Object).Count -eq 0 -and $Role.AllowedTenants -contains 'AllTenants') {
        return $true
    }

    if ($TenantFilter -eq 'AllTenants' -and $ApiRole -match 'Write$') {
        return $false
    }

    if ($TenantFilter -eq 'AllTenants' -and $ApiRole -match 'Read$') {
        return $true
    }

    $ExpandedAllowedTenants = foreach ($AllowedItem in $Role.AllowedTenants) {
        if ($AllowedItem -is [PSCustomObject] -and $AllowedItem.type -eq 'Group') {
            try {
                $GroupMembers = Expand-CIPPTenantGroups -TenantFilter @($AllowedItem)
                $GroupMembers | ForEach-Object { $_.addedFields.customerId }
            } catch {
                Write-Warning "Failed to expand allowed tenant group '$($AllowedItem.label)': $($_.Exception.Message)"
                @()
            }
        } else {
            $AllowedItem
        }
    }

    $ExpandedBlockedTenants = foreach ($BlockedItem in $Role.BlockedTenants) {
        if ($BlockedItem -is [PSCustomObject] -and $BlockedItem.type -eq 'Group') {
            try {
                $GroupMembers = Expand-CIPPTenantGroups -TenantFilter @($BlockedItem)
                $GroupMembers | ForEach-Object { $_.addedFields.customerId }
            } catch {
                Write-Warning "Failed to expand blocked tenant group '$($BlockedItem.label)': $($_.Exception.Message)"
                @()
            }
        } else {
            $BlockedItem
        }
    }

    if ($ExpandedAllowedTenants -contains 'AllTenants') {
        $AllowedTenants = $Tenants.customerId
    } else {
        $AllowedTenants = $ExpandedAllowedTenants
    }

    # A group is authorized by identity against the role's granted groups, never by expanding
    # members into an allow. Its members only matter to deny: a block reaching any of them, or a
    # member this role excludes.
    if ($IsGroup) {
        $AllowedGroupIds = @(foreach ($AllowedItem in $Role.AllowedTenants) {
                if ($AllowedItem -is [PSCustomObject] -and $AllowedItem.type -eq 'Group') { $AllowedItem.value }
            })
        $Members = @(try {
                Expand-CIPPTenantGroups -TenantFilter @([PSCustomObject]@{ type = 'Group'; value = $TenantFilter; label = $TenantFilter }) | ForEach-Object { $_.addedFields.customerId }
            } catch {
                Write-Warning "Failed to expand requested tenant group '$TenantFilter': $($_.Exception.Message)"
            })
        if ($TreatUnresolvedAsInScope) {
            return ($AllowedGroupIds -contains $TenantFilter -or $Members.Where({ $AllowedTenants -contains $_ -and $ExpandedBlockedTenants -notcontains $_ }, 'First').Count -gt 0)
        }
        return ($AllowedGroupIds -contains $TenantFilter -and $Members.Where({ $ExpandedBlockedTenants -contains $_ }, 'First').Count -eq 0)
    }

    $Tenant = ($Tenants | Where-Object { $TenantFilter -eq $_.customerId -or $TenantFilter -eq $_.defaultDomainName }).customerId
    if ($Tenant) {
        return ($AllowedTenants -contains $Tenant -and $ExpandedBlockedTenants -notcontains $Tenant)
    }

    # No filter (or an AllTenants request the ApiRole branches above did not handle):
    # the request is not scoped to a resolvable single tenant, so the role is in scope.
    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return $true
    }

    # Filter present but resolves to no known tenant: denied, unless the caller opted
    # into fail-closed block semantics.
    return $TreatUnresolvedAsInScope.IsPresent
}
