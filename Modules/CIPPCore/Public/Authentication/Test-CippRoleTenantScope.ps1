function Test-CippRoleTenantScope {
    <#
    .SYNOPSIS
        Whether a custom role's tenant scope covers the request's target tenant (or group).

    .DESCRIPTION
        Extracted from the per-endpoint allow path in Test-CIPPAccess. Same rules:
        AllTenants with no blocked list, AllTenants Write/Read request special-cases,
        group-shaped body authorized by group identity (no member expand), then
        allowed-minus-blocked after expanding tenant groups.

        Unknown / missing / unmapped tenant filters return $true. Callers interpret that
        differently: the allow path treats it as allow (legacy quirk); the
        BlockedEndpoints pass treats it as in-scope so the deny still applies
        (fail closed). Do not fall back to $env:TenantID — that is the partner
        home tenant, not a customer. Do not "align" those call sites without an
        explicit decision.

    .PARAMETER Role
        Role permission object from Get-CIPPRolePermissions (AllowedTenants, BlockedTenants, ...).

    .PARAMETER TenantFilter
        Resolved tenant filter string (customerId, domain, AllTenants, or group value when body is Group-shaped).

    .PARAMETER Tenants
        Tenant list from Get-Tenants -IncludeErrors (used to resolve filter and expand AllTenants).

    .PARAMETER Request
        HTTP request; Body.tenantFilter.type -eq 'Group' selects group-identity authorization.

    .PARAMETER ApiRole
        Endpoint permission string; used for AllTenants Write$ / Read$ branches.

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

        [Parameter(Mandatory = $true)]
        $Request,

        [Parameter(Mandatory = $true)]
        [string]$ApiRole
    )

    $Tenants = @($Tenants)

    if (($Role.BlockedTenants | Measure-Object).Count -eq 0 -and $Role.AllowedTenants -contains 'AllTenants') {
        return $true
    }

    if ($TenantFilter -eq 'AllTenants' -and $ApiRole -match 'Write$') {
        return $false
    }

    if ($TenantFilter -eq 'AllTenants' -and $ApiRole -match 'Read$') {
        return $true
    }

    # A requested tenant GROUP arrives as a complex body object
    # {type:'Group', value:<guid>}. Authorize it by group identity against the
    # role's granted groups - never by expanding members - so it can't fall
    # through to the unknown-tenant allow below. Query-string filters are plain
    # strings and cannot carry a group, so only the body object is a group request.
    if ($Request.Body.tenantFilter.type -eq 'Group') {
        $RequestedGroup = $Request.Body.tenantFilter.value
        $AllowedGroupIds = @(foreach ($AllowedItem in $Role.AllowedTenants) {
                if ($AllowedItem -is [PSCustomObject] -and $AllowedItem.type -eq 'Group') { $AllowedItem.value }
            })
        return ($AllowedGroupIds -contains $RequestedGroup)
    }

    $Tenant = ($Tenants | Where-Object { $TenantFilter -eq $_.customerId -or $TenantFilter -eq $_.defaultDomainName }).customerId

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

    if ($Tenant) {
        return ($AllowedTenants -contains $Tenant -and $ExpandedBlockedTenants -notcontains $Tenant)
    }

    # Unmapped tenant filter: true for both call sites (allow quirk / block fail-closed).
    return $true
}
