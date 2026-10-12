function Get-CIPPBaselineTeamsFederationConfigurationState {
    <#
    .SYNOPSIS
        Prepare hook for TeamsFederationConfiguration: external federation posture.
    .DESCRIPTION
        Grades the classic's five facts - the two consumer-access switches, whether
        federation is on at all, and the allow/block domain lists - normalized the way the
        classic's report normalized them, because the ConfigAPI GET shape is asymmetric with
        its PUT shape: the GET nests the allow-list under AllowedDomains.AllowedDomain
        (allow-all = an empty object), items arrive as strings or {Domain} objects, and both
        lists sort before comparing. An allow-all posture reads as the literal string
        'AllowAllKnownDomains' so the drift row says what it means.

        The four modes decide which facts have which expected value; the domain list only
        participates in the Specific modes. Everything the executor needs to rebuild the PUT
        payload is carried, because the PUT shape cannot be derived from the graded values.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $State = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'CsTenantFederationConfiguration') | Select-Object -First 1
    if (-not $State) { return @{ Current = $null } }

    $V = $Item.Variables
    $DomainControl = "$($V.DomainControl.value ?? $V.DomainControl)"
    if ($DomainControl -notin @('AllowAllExternal', 'BlockAllExternal', 'AllowSpecificExternal', 'BlockSpecificExternal')) {
        return @{ Current = $null }
    }
    $AllowTeamsConsumer = [bool]($V.AllowTeamsConsumer -eq $true)
    $AllowTeamsConsumerInbound = [bool]($V.AllowTeamsConsumerInbound -eq $true)

    $DomainList = @()
    if (-not [string]::IsNullOrWhiteSpace("$($V.DomainList)")) {
        $DomainList = @("$($V.DomainList)".Split(',').Trim() | Where-Object { $_ }) | Sort-Object
    }

    # PUT shapes are GET-symmetric: allow-all = an empty OBJECT (AllowAllKnownDomains), a
    # specific list = {Domain} objects under AllowedDomain. NEVER an empty array or an
    # AllowList envelope - the ConfigAPI coerces those into an explicit EMPTY allow list
    # (federation with nobody) while reporting success (CyberDrain/CIPP#364).
    switch ($DomainControl) {
        'AllowAllExternal' { $AllowFederatedUsers = $true; $ExpectedAllowed = 'AllowAllKnownDomains'; $ExpectedBlocked = @(); $AllowedPayload = @{} }
        'BlockAllExternal' { $AllowFederatedUsers = $false; $ExpectedAllowed = 'AllowAllKnownDomains'; $ExpectedBlocked = @(); $AllowedPayload = @{} }
        'AllowSpecificExternal' { $AllowFederatedUsers = $true; $ExpectedAllowed = @($DomainList); $ExpectedBlocked = @(); $AllowedPayload = @{ AllowedDomain = @($DomainList | ForEach-Object { @{ Domain = $_ } }) } }
        'BlockSpecificExternal' { $AllowFederatedUsers = $true; $ExpectedAllowed = 'AllowAllKnownDomains'; $ExpectedBlocked = @($DomainList); $AllowedPayload = @{} }
    }

    # GET shape: allow-all = AllowedDomains with no AllowedDomain member. A member that is
    # PRESENT but EMPTY ({"AllowedDomain":[]}) is an explicit empty allow list - federation
    # with nobody, the #364 breakage state - so key off presence, not item count, or broken
    # tenants grade as aligned forever.
    $CurrentAllowedDomains = @()
    $AllowedNode = $State.AllowedDomains
    $HasExplicitAllowList = [bool]($AllowedNode -and ($AllowedNode.PSObject.Properties.Name -contains 'AllowedDomain'))
    if ($HasExplicitAllowList -and $AllowedNode.AllowedDomain) {
        $CurrentAllowedDomains = @($AllowedNode.AllowedDomain | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.Domain) { "$($_.Domain)" } else { "$_" } }) | Sort-Object
    }
    $CurrentBlockedDomains = @()
    if ($State.BlockedDomains) {
        $CurrentBlockedDomains = @($State.BlockedDomains | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.Domain) { "$($_.Domain)" } else { "$_" } }) | Sort-Object
    }
    # The comma is load-bearing: an if-expression's pipeline output unwraps one array
    # level, which turned a single allowed domain into a SCALAR - graded against the
    # expected ARRAY, identical text drifted forever.
    $CurrentAllowed = if (-not $HasExplicitAllowList) { 'AllowAllKnownDomains' } else { , @($CurrentAllowedDomains) }

    # BlockAllExternal only grades the federation switch - the classic ignored both lists there.
    if ($DomainControl -eq 'BlockAllExternal') {
        $CurrentAllowed = $ExpectedAllowed
        $CurrentBlockedDomains = @()
    }

    $Expected = [PSCustomObject]@{
        allowTeamsConsumer        = $AllowTeamsConsumer
        allowTeamsConsumerInbound = $AllowTeamsConsumerInbound
        allowFederatedUsers       = $AllowFederatedUsers
        allowedDomains            = $ExpectedAllowed
        blockedDomains            = @($ExpectedBlocked)
    }
    $Current = [PSCustomObject]@{
        allowTeamsConsumer        = [bool]$State.AllowTeamsConsumer
        allowTeamsConsumerInbound = [bool]$State.AllowTeamsConsumerInbound
        allowFederatedUsers       = [bool]$State.AllowFederatedUsers
        allowedDomains            = $CurrentAllowed
        blockedDomains            = @($CurrentBlockedDomains)
    }
    # Carried for the executor - the ConfigAPI PUT shape differs from the graded one.
    $Current | Add-Member -NotePropertyName 'writePayload' -NotePropertyValue ([PSCustomObject]@{
            AllowTeamsConsumer        = $AllowTeamsConsumer
            AllowTeamsConsumerInbound = $AllowTeamsConsumerInbound
            AllowFederatedUsers       = $AllowFederatedUsers
            AllowedDomains            = $AllowedPayload
            BlockedDomains            = @($ExpectedBlocked | ForEach-Object { @{ Domain = $_ } })
        })

    @{ Expected = $Expected; Current = $Current }
}
