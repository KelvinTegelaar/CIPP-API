function Invoke-CIPPBaselineTeamsFederationConfiguration {
    <#
    .SYNOPSIS
        TeamsFederationConfiguration executor: writes the federation posture.
    .DESCRIPTION
        One Set against the ConfigAPI with the hook's carried payload - the PUT shape is
        GET-symmetric ({} for allow-all, {Domain} objects under AllowedDomain for a list)
        and differs from the graded shape, which is why the hook builds it rather than this
        executor deriving it. An empty ARRAY for AllowedDomains would be coerced into an
        explicit empty allow list - federation with nobody (CyberDrain/CIPP#364).
        -NoRead sends the bare properties exactly like the admin center does; the classic's
        comment records that the ConfigAPI rejects the enveloped form for this write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Payload = $Current.writePayload
    if (-not $Payload) { return }

    $Parameters = @{
        Identity                  = 'Global'
        AllowTeamsConsumer        = [bool]$Payload.AllowTeamsConsumer
        AllowTeamsConsumerInbound = [bool]$Payload.AllowTeamsConsumerInbound
        AllowFederatedUsers       = [bool]$Payload.AllowFederatedUsers
        AllowedDomains            = $Payload.AllowedDomains
        BlockedDomains            = @($Payload.BlockedDomains)
    }
    $null = New-TeamsRequestV2 -TenantFilter $TenantFilter -Type 'TenantFederationConfiguration' -Action Set -Parameters $Parameters -NoRead
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Updated the Teams federation configuration.' -Sev 'Info'
}
