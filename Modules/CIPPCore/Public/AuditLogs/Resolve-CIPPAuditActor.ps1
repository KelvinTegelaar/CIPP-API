function Resolve-CIPPAuditActor {
    <#
    .SYNOPSIS
        Classifies the actor named in an audit record: the tenant's own user, a partner (GDAP) identity, CIPP itself, or an application.
    .DESCRIPTION
        Customer-tenant audit records name a partner identity in two shapes - user_<objectid>@<tenant>.onmicrosoft.com
        (Entra) and <customer>.onmicrosoft.com\tenant: <partner tenant id>, object: <objectid> (Exchange) - the same
        shapes the audit-log pipeline maps back to partner users. This resolves them against the partner user
        lookup, tells this partner tenant from another partner by tenant id, recognises CIPP's own SAM application
        by app id, and returns the kind with the resolved name, so a case can show partner and CIPP actions as
        such instead of as an unknown actor.
    .PARAMETER Actor
        The actor as written in the record: UserId, UserKey, or the initiating user principal name.
    .PARAMETER ActorType
        'User' or 'Application' when the record says which (Entra directory audits do). Defaults to User.
    .PARAMETER AppId
        The application (client) id when the record was app-initiated.
    .PARAMETER PartnerUserLookup
        Hashtable of partner-tenant users keyed by object id (Get-CIPPPartnerUserLookup). Without it a partner
        identity is still recognised by its shape, just not named.
    .OUTPUTS
        [pscustomobject] { Kind = User | Partner | OtherPartner | CIPP | Application | System; Actor; PartnerTenantId }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Actor,
        [string]$ActorType = 'User',
        [string]$AppId,
        [hashtable]$PartnerUserLookup = @{}
    )
    $Raw = [string]$Actor
    $Answer = { param($Kind, $Name, $TenantId) [pscustomobject]@{ Kind = $Kind; Actor = $Name; PartnerTenantId = $TenantId } }
    $NameOf = { param($Id, $Fallback) if ($Id -and $PartnerUserLookup.ContainsKey($Id)) { [string]$PartnerUserLookup[$Id].userPrincipalName } else { $Fallback } }
    $CippAppId = [string]$env:ApplicationID
    $CippTenantId = [string]$env:TenantID

    if ($CippAppId -and (($AppId -and $AppId -eq $CippAppId) -or $Raw -eq $CippAppId)) {
        return & $Answer 'CIPP' 'CIPP (service principal)' $CippTenantId
    }
    if ($ActorType -eq 'Application') {
        return & $Answer 'Application' ($(if ($Raw) { $Raw } else { $AppId })) $null
    }
    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return & $Answer 'User' $Raw $null
    }
    if ($Raw -match '(?i)^NT AUTHORITY\\SYSTEM|^S-1-5-18$|Microsoft\.Exchange\.ServiceHost') {
        return & $Answer 'System' $Raw $null
    }
    # Entra shape: user_<32 hex>@<tenant>.onmicrosoft.com - the hex is the partner-tenant object id
    if ($Raw -match '(?i)user_([0-9a-f]{32})@[^@]+\.onmicrosoft\.com') {
        $Hex = $Matches[1].ToLowerInvariant()
        $Id = "$($Hex.Substring(0, 8))-$($Hex.Substring(8, 4))-$($Hex.Substring(12, 4))-$($Hex.Substring(16, 4))-$($Hex.Substring(20, 12))"
        # Known to this partner, or unknowable (no lookup): this partner. Known lookup, unknown id: another one.
        $Kind = if ($PartnerUserLookup.Count -eq 0 -or $PartnerUserLookup.ContainsKey($Id)) { 'Partner' } else { 'OtherPartner' }
        return & $Answer $Kind (& $NameOf $Id $Raw) $null
    }
    # Exchange shape: <customer>.onmicrosoft.com\tenant: <partner tenant id>, object: <object id>
    if ($Raw -match '(?i)\\tenant:\s*([0-9a-f-]{36}),\s*object:\s*([0-9a-f-]{36})') {
        $TenantId = $Matches[1]
        $Id = $Matches[2]
        $Kind = if ($CippTenantId -and $TenantId -eq $CippTenantId) { 'Partner' } else { 'OtherPartner' }
        return & $Answer $Kind (& $NameOf $Id $Raw) $TenantId
    }
    # A bare object id as the actor is a service principal acting app-only
    if ($Raw -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        return & $Answer 'Application' $Raw $null
    }
    return & $Answer 'User' $Raw $null
}
