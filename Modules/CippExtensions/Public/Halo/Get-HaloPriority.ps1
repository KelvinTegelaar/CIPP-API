function Get-HaloPriority {
    <#
    .SYNOPSIS
        Get HaloPSA Priorities for use in the integration UI dropdown, restricted to the SLA
        attached to the configured Ticket Type so admins can only pick a priority that the
        ticket would actually be allowed to use.
    .DESCRIPTION
        HaloPSA priorities only have meaningful effect within the SLA they belong to (response
        and resolution targets are defined per priority per SLA). Returning all priorities lets
        admins pick one that doesn't apply to the chosen Ticket Type, producing tickets that
        either reject the priority outright or fall back to the SLA default with no warning.

        Looks up the ticket type's sla_id, then returns the priorities tied to that SLA.
    .PARAMETER TicketType
        Ticket type to scope the priorities to. The settings page passes the value currently
        selected in the form so the list follows the dropdown without needing a save first.
        Falls back to the saved ticket type when not supplied.
    #>
    [CmdletBinding()]
    param (
        $TicketType
    )
    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).HaloPSA
        $Token = Get-HaloToken -configuration $Configuration
        if (-not $TicketType) {
            $TicketType = $Configuration.TicketType.value ?? $Configuration.TicketType
        }

        if (-not $TicketType) {
            return @(@{
                    name  = 'Select a Ticket Type first to see available priorities'
                    priorityid = -1
                })
        }

        $Headers = @{ Authorization = "Bearer $($Token.access_token)" }
        $UserAgent = Get-CippUserAgent
        $SlaId = Get-HaloTicketTypeSlaId -TicketType $TicketType -Configuration $Configuration -Token $Token

        if (-not $SlaId) {
            # New-HaloPSATicket applies the same test and omits priority_id entirely for this
            # ticket type, so the message describes what will actually happen rather than just
            # explaining an empty list.
            return @(@{
                    name       = 'The selected Ticket Type has no SLA attached, so there are no priorities to pick from. Tickets will be created without a priority and HaloPSA will apply its own. Attach an SLA to the ticket type in HaloPSA to choose one here.'
                    priorityid = -1
                })
        }

        # The /SLA/{id} response shape varies between Halo versions: some return full priority
        # objects under .priorities, some only IDs. Resolve both by fetching the canonical
        # priority list and filtering by ID, which works regardless of the SLA payload shape.
        $Sla = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Configuration.ResourceURL)/SLA/$SlaId" -ContentType 'application/json' -Method GET -Headers $Headers

        $SlaPriorityIds = @()
        if ($Sla.priorities) {
            $SlaPriorityIds = foreach ($p in $Sla.priorities) {
                if ($p.id) { $p.id } else { $p }
            }
        }

        $AllPriorities = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Configuration.ResourceURL)/Priority" -ContentType 'application/json' -Method GET -Headers $Headers

        if ($SlaPriorityIds.Count -gt 0) {
            $AllPriorities | Where-Object { $_.id -in $SlaPriorityIds } | Sort-Object -Property priorityorder, name
        } else {
            # SLA exists but doesn't expose a priority list - return all priorities as a fallback
            # so the dropdown isn't empty, with a leading hint row.
            @(@{ name = '(SLA returned no priority list - showing all priorities)'; priorityid = -1 }) +
                ($AllPriorities | Sort-Object -Property priorityorder, name)
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        @(@{ name = "Could not get HaloPSA Priorities, error: $Message"; id = '' })
    }
}
