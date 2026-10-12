function Get-CIPPBaselineCollaborationDomainRestrictionState {
    <#
    .SYNOPSIS
        Prepare hook for CollaborationDomainRestriction: the B2B invitation allow-list.
    .DESCRIPTION
        Grades the sorted allowed-domains list on the tenant's B2B management policy
        against the configured list. The policy is a GUID-keyed collection with no default
        singleton - org-default preferred, first otherwise - and the actual settings live in
        definition[0] as a JSON string.

        The FULL parsed definition is carried for the executor: the write must rebuild the
        domain policy on top of it so sibling settings (AutoRedeemPolicy) survive.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'B2BManagementPolicy')
    if ($Policies.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'B2BManagementPolicy')) {
        return @{ Current = $null }
    }

    $Desired = @("$($Item.Variables.allowedDomains)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
    if ($Desired.Count -eq 0) { return @{ Current = $null } }

    $Policy = @($Policies | Where-Object { $_.isOrganizationDefault -eq $true }) | Select-Object -First 1
    if (-not $Policy) { $Policy = $Policies | Select-Object -First 1 }
    $Definition = $(if ($Policy.definition) { try { @($Policy.definition)[0] | ConvertFrom-Json -ErrorAction Stop } catch { $null } })
    $DomainPolicy = $Definition.B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy

    $Current = [PSCustomObject]@{
        allowedDomains = @($DomainPolicy.AllowedDomains | Sort-Object)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'policyId' -NotePropertyValue "$($Policy.id)"
    $Current | Add-Member -NotePropertyName 'existingDefinition' -NotePropertyValue $Definition

    @{
        Expected = [PSCustomObject]@{ allowedDomains = @($Desired) }
        Current  = $Current
    }
}
