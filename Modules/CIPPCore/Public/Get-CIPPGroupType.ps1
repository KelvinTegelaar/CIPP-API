function Get-CIPPGroupType {
    <#
    .SYNOPSIS
    Resolves the Microsoft group type for a group by looking it up.

    .DESCRIPTION
    Fetches the group from Graph and classifies it into one of the canonical types:
    Microsoft 365, Mail-Enabled Security, Distribution List, or Security.

    Graph cannot write membership/ownership on classic distribution lists or mail-enabled
    security groups, so callers use IsExchangeBacked to pick Exchange vs Graph.

    When Graph returns nothing usable (404, addressed by mail/display name, etc.), falls
    back to Get-DistributionGroup in Exchange, then to -FallbackGroupType if supplied.

    .PARAMETER GroupId
    Group object id, mail, or Exchange identity.

    .PARAMETER TenantFilter
    Tenant id or default domain.

    .PARAMETER FallbackGroupType
    Used only when Graph and Exchange both fail to classify the group. Accepts common
    casing variants (e.g. 'Distribution list' / 'Distribution List').

    .OUTPUTS
    PSCustomObject with GroupId, DisplayName, GroupType, IsExchangeBacked, GroupObject.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$FallbackGroupType
    )

    $GroupObject = $null
    try {
        $GroupObject = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId`?`$select=id,displayName,groupTypes,mailEnabled,securityEnabled" -tenantid $TenantFilter
    } catch {
        Write-Information "Get-CIPPGroupType: Graph lookup failed for '$GroupId': $($_.Exception.Message)"
    }

    $GroupType = $null
    $DisplayName = $null
    $ResolvedId = $GroupId

    if ($null -ne $GroupObject -and ($null -ne $GroupObject.mailEnabled -or $null -ne $GroupObject.securityEnabled)) {
        if ($GroupObject.groupTypes -contains 'Unified') {
            $GroupType = 'Microsoft 365'
        } elseif ($GroupObject.mailEnabled -and $GroupObject.securityEnabled) {
            $GroupType = 'Mail-Enabled Security'
        } elseif ($GroupObject.mailEnabled) {
            $GroupType = 'Distribution List'
        } else {
            $GroupType = 'Security'
        }
        $DisplayName = $GroupObject.displayName
        if ($GroupObject.id) { $ResolvedId = $GroupObject.id }
    }

    # Graph missed (wrong id shape, mail nickname, etc.) — Exchange still knows classic DLs / MES.
    if (-not $GroupType) {
        try {
            $ExoGroup = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroup' -cmdParams @{ Identity = $GroupId } -Select 'Guid,DisplayName,RecipientTypeDetails' -UseSystemMailbox $true
            if ($ExoGroup) {
                $GroupType = if ($ExoGroup.RecipientTypeDetails -eq 'MailUniversalSecurityGroup') {
                    'Mail-Enabled Security'
                } else {
                    'Distribution List'
                }
                $DisplayName = $ExoGroup.DisplayName ?? $DisplayName
                if ($ExoGroup.Guid) { $ResolvedId = [string]$ExoGroup.Guid }
            }
        } catch {
            Write-Information "Get-CIPPGroupType: Exchange lookup failed for '$GroupId': $($_.Exception.Message)"
        }
    }

    if (-not $GroupType) {
        $GroupType = switch -Regex ($FallbackGroupType) {
            '^(?i)microsoft\s*365$|^(?i)unified$' { 'Microsoft 365'; break }
            '^(?i)mail-enabled\s*security$' { 'Mail-Enabled Security'; break }
            '^(?i)distribution\s*list$' { 'Distribution List'; break }
            '^(?i)security$' { 'Security'; break }
            default { if ($FallbackGroupType) { $FallbackGroupType } else { 'Security' } }
        }
    }

    if (-not $DisplayName) {
        $DisplayName = $GroupObject.displayName ?? $GroupId
    }

    return [pscustomobject]@{
        GroupId          = $ResolvedId
        DisplayName      = $DisplayName
        GroupType        = $GroupType
        IsExchangeBacked = ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security')
        GroupObject      = $GroupObject
    }
}
