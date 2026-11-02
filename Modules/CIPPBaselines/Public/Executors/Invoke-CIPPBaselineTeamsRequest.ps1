function Invoke-CIPPBaselineTeamsRequest {
    <#
    .SYNOPSIS
        TeamsRequest executor: runs a definition's ordered cmdlets[] against one tenant.
    .DESCRIPTION
        One script for the whole request type - mirrors the ExoRequest executor shape but
        writes through New-TeamsRequestV2 (the Teams admin ConfigAPI), because the classic
        Cs* policy surface returns 403 under CSP/GDAP. Each entry is { cmdlet, identity,
        params, continueOnError }: cmdlet is the classic name (e.g.
        'Set-CsTeamsMeetingPolicy') - New-TeamsRequestV2 strips the verb and maps the noun
        to its ConfigAPI type; identity defaults to 'Global'. The spec arrives fully
        rendered (%var% + tenant tokens resolved).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        # The read result. Unused here; every executor takes the same arguments.
        $Current
    )

    foreach ($Step in @($Remediate.cmdlets)) {
        if (-not $Step) { continue }
        $CmdParams = @{}
        foreach ($Property in ($Step.params ?? [PSCustomObject]@{}).PSObject.Properties) {
            $CmdParams[$Property.Name] = $Property.Value
        }
        try {
            $null = New-TeamsRequestV2 -TenantFilter $TenantFilter -Type $Step.cmdlet -Action 'Set' -Identity ($Step.identity ?? 'Global') -Parameters $CmdParams
        } catch {
            if ($Step.continueOnError -eq $true) {
                Write-Information "Baselines: $($Step.cmdlet) on $TenantFilter continued past: $($_.Exception.Message)"
            } else { throw }
        }
    }
}
