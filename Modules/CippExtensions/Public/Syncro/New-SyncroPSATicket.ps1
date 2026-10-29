function New-SyncroPSATicket {
    <#
    .SYNOPSIS
        Creates a ticket in Syncro for a CIPP alert.
    .DESCRIPTION
        First-step Syncro PSA support: one new ticket per alert, against the Syncro customer the
        tenant is mapped to, with the right priority. Consolidation onto an existing ticket and
        linking the ticket to an affected contact are not implemented yet, so every call creates
        a ticket.

        The alert body is attached as a hidden (internal) comment with customer email suppressed,
        so raising a ticket never emails the customer. The subject goes on the ticket itself.

        Returns a single line the alert pipeline reads: 'Ticket created in Syncro: ...' on
        success, 'Failed to send ticket to Syncro: ...' on failure. Send-CIPPAlert keys off the
        Failed/Error prefix, so the failure text must keep it.
    .PARAMETER Title
        Ticket subject.
    .PARAMETER Description
        Ticket body (HTML from the alert pipeline).
    .PARAMETER Client
        Syncro customer id the ticket belongs to.
    .PARAMETER TicketPriority
        Per-alert priority override. Untyped so callers can hand over either the raw string or
        the {label, value} shape the alert form stores. Wins over the integration-wide
        DefaultPriority when it is a recognisable Syncro priority.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        $Title,
        $Description,
        $Client,
        $TicketPriority
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).Syncro

    $CustomerId = 0
    if (-not [int]::TryParse("$Client", [ref]$CustomerId) -or $CustomerId -le 0) {
        $Message = "'$Client' is not a usable Syncro customer id. Map the tenant under Settings > Integrations > Syncro."
        Write-LogMessage -message "Failed to send ticket to Syncro: $Message" -API 'SyncroTicket' -sev Error
        return "Failed to send ticket to Syncro: $Message"
    }

    # Priority sources in precedence order: the per-alert override, then the integration-wide
    # default. Each is only used when it is a recognisable Syncro priority; otherwise the next
    # source is tried, and with none left the ticket is sent without a priority so Syncro
    # applies its own default (Normal).
    $PrioritySources = @(
        @{ Label = 'alert'; Value = $TicketPriority }
        @{ Label = 'Syncro.DefaultPriority'; Value = $Configuration.DefaultPriority }
    )
    $ResolvedPriority = $null
    foreach ($Source in $PrioritySources) {
        $Raw = $Source.Value.value ?? $Source.Value
        if ([string]::IsNullOrWhiteSpace("$Raw")) { continue }
        $Candidate = Get-SyncroPriority -Priority $Source.Value
        if ($Candidate) {
            $ResolvedPriority = $Candidate
            Write-Information "Syncro ticket priority $Candidate from $($Source.Label)"
            break
        }
        Write-LogMessage -message "Syncro priority value '$Raw' from $($Source.Label) is not a Syncro priority (expected 0 Urgent, 1 High, 2 Normal or 3 Low) - falling back" -API 'SyncroTicket' -sev Warning
    }

    $Ticket = [ordered]@{
        customer_id         = $CustomerId
        subject             = $Title
        comments_attributes = @(
            [ordered]@{
                subject      = 'Initial Issue'
                body         = $Description
                hidden       = $true
                do_not_email = $true
            }
        )
    }
    if ($ResolvedPriority) { $Ticket.priority = $ResolvedPriority }

    # Both optional free-text settings: Syncro accepts any value but shows them in its own
    # pick lists, so an admin can match an existing Problem Type / Status by typing it exactly.
    $ProblemType = "$($Configuration.ProblemType.value ?? $Configuration.ProblemType)".Trim()
    if ($ProblemType) { $Ticket.problem_type = $ProblemType }
    $Status = "$($Configuration.TicketStatus.value ?? $Configuration.TicketStatus)".Trim()
    if ($Status) { $Ticket.status = $Status }

    $Body = ConvertTo-Json -InputObject $Ticket -Depth 10 -Compress
    Write-Information 'Sending ticket to Syncro'
    Write-Information $Body
    try {
        if ($PSCmdlet.ShouldProcess('Send ticket to Syncro', 'Create ticket')) {
            $Response = Invoke-SyncroRequest -Configuration $Configuration -Endpoint '/tickets' -Method POST -Body $Body
            $Created = $Response.ticket
            if (-not $Created.id) {
                throw 'Syncro accepted the request but returned no ticket.'
            }
            $Label = if ($Created.number) { "#$($Created.number) (id $($Created.id))" } else { "id $($Created.id)" }
            Write-Information "Ticket created in Syncro: $Label"
            return "Ticket created in Syncro: $Label"
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        Write-LogMessage -message "Failed to send ticket to Syncro: $Message" -API 'SyncroTicket' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information "Failed to send ticket to Syncro: $Message"
        Write-Information "Body we tried to ship: $Body"
        return "Failed to send ticket to Syncro: $Message"
    }
}
