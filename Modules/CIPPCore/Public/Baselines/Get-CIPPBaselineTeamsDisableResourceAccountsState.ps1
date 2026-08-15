function Get-CIPPBaselineTeamsDisableResourceAccountsState {
    <#
    .SYNOPSIS
        Prepare hook for TeamsDisableResourceAccounts: auto attendant and call queue resource
        accounts whose Entra account is still enabled.
    .DESCRIPTION
        Joins the TeamsResourceAccounts cache against the Users cache on objectId. Resource
        accounts need no sign-in - they exist to own a phone number - so an enabled one is a
        credential nobody monitors.

        An empty resource-account cache is NOT the same as 'all blocked': it more likely means
        the Teams surface was not collected. That returns a null Current so the engine reports
        No Data and retries, rather than scoring the tenant compliant for the wrong reason.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Accounts = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'TeamsResourceAccounts' | Where-Object { $_ })
    if ($Accounts.Count -eq 0) {
        # Plenty of tenants run no auto attendants or call queues at all. Once the type has
        # been collected, empty is the answer - nothing to disable, so compliant. Before that
        # it is unknown, and the engine collects and retries.
        if (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'TeamsResourceAccounts') {
            return @{ Current = [PSCustomObject]@{ offenders = @(); targets = @() } }
        }
        return @{ Current = $null }
    }

    # Users is the SECOND cache - see Get-CIPPBaselineCacheRows.
    $Users = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users')
    $EnabledIds = @{}
    foreach ($User in $Users) {
        if ($User.accountEnabled -eq $true -and $User.onPremisesSyncEnabled -ne $true) { $EnabledIds["$($User.id)"] = $true }
    }

    $Enabled = @($Accounts | Where-Object { $_.objectId -and $EnabledIds.ContainsKey("$($_.objectId)") })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Enabled | ForEach-Object { "$($_.userPrincipalName ?? $_.displayName)" } | Sort-Object)
            targets   = @($Enabled | ForEach-Object { [PSCustomObject]@{ id = "$($_.objectId)" } })
        }
    }
}
