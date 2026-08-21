function Invoke-CIPPBaselineTeamsFederationConfiguration {
    <#
    .SYNOPSIS
        TeamsFederationConfiguration executor: writes the federation posture.
    .DESCRIPTION
        One Set against the ConfigAPI with the hook's carried payload - the PUT shape
        (AllowList envelope, bare arrays) differs from both the GET shape and the graded
        shape, which is why the hook builds it rather than this executor deriving it.
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
