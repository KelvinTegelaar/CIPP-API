function Get-HaloTicketTypeSlaId {
    <#
    .SYNOPSIS
        Resolve the SLA id attached to a HaloPSA ticket type, or $null when it has none.
    .DESCRIPTION
        Priorities in HaloPSA are defined per priority per SLA - the same priority_id means a
        different thing under a different SLA (response and resolution targets are set on the
        SLA/priority pair). A ticket type with no SLA therefore has no priority set that can be
        meaningfully chosen from, which is why both the settings dropdown and the ticket writer
        need to agree on whether one is attached.

        Shared by Get-HaloPriority (to decide whether there is anything to offer) and
        New-HaloPSATicket (to decide whether to send priority_id at all), so the two cannot drift
        apart and start disagreeing about the same ticket type.
    .PARAMETER TicketType
        The ticket type id to resolve.
    .PARAMETER Configuration
        The HaloPSA extension configuration, for ResourceURL.
    .PARAMETER Token
        An existing Halo token, so callers that already hold one do not fetch a second.
    .OUTPUTS
        [int] the SLA id, or $null when the ticket type has no SLA or could not be read.
    #>
    [CmdletBinding()]
    param (
        $TicketType,
        $Configuration,
        $Token
    )

    if (-not $TicketType) { return $null }

    try {
        $Headers = @{ Authorization = "Bearer $($Token.access_token)" }
        $TicketTypeRecord = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/tickettype/$TicketType" -ContentType 'application/json' -Method GET -Headers $Headers

        # Halo's /tickettype/{id} response uses different field names for the linked SLA across
        # versions. Check the known variants in order and take the first usable match. Halo uses
        # -1 for "none", so anything not greater than zero counts as no SLA.
        foreach ($Field in @('default_sla', 'default_sla_id', 'sla_id', 'slaid', 'sla')) {
            $Value = $TicketTypeRecord.$Field
            if ($Value -and ([int]$Value) -gt 0) {
                return [int]$Value
            }
        }
        return $null
    } catch {
        # Callers treat $null as "no SLA" and omit the priority, which is the safe direction:
        # a transient lookup failure should not put an arbitrary priority on a ticket.
        Write-Information "Could not resolve the SLA for HaloPSA ticket type $TicketType : $($_.Exception.Message)"
        return $null
    }
}
