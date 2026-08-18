function Get-HaloRequestSource {
    <#
    .SYNOPSIS
        Get the HaloPSA request sources available to stamp on CIPP-generated tickets.
    .DESCRIPTION
        Halo records tickets created over the API as "Manual" unless the payload carries a source,
        so CIPP's tickets are indistinguishable from ones an agent raised by hand. Request sources
        have no dedicated endpoint - they are lookup type 22 - and the list is instance-wide rather
        than scoped to a ticket type, so unlike the priority and outcome lookups this takes no
        TicketType parameter.

        Source ids legitimately include 0 (Email) and negative values (Halo's built-in integration
        sources, e.g. -9 Ninja RMM), so callers must not treat an id as absent because it is falsy.
    .EXAMPLE
        Get-HaloRequestSource

    #>
    [CmdletBinding()]
    param ()
    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).HaloPSA
        $Token = Get-HaloToken -configuration $Configuration

        $Response = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/lookup?lookupid=22&showall=true" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" }

        # Halo returns a bare array here, but some of its lookup responses wrap the rows. Handle
        # both so a version difference reads as "no sources" rather than throwing.
        $Sources = if ($Response -is [array]) { $Response } elseif ($Response.lookups) { $Response.lookups } else { @($Response) }

        # Project to what the dropdown needs. The integration form persists the whole selected
        # option - label, value and the raw API row - into the extension config blob, so returning
        # the raw lookup rows would store that noise alongside it.
        @($Sources | Where-Object { $null -ne $_.id -and $_.name } | ForEach-Object {
                [PSCustomObject]@{
                    name = "$($_.name)"
                    id   = [int]$_.id
                }
            } | Sort-Object -Property name)
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        @(@{name = "Could not get HaloPSA Request Sources, error: $Message"; id = '' })
    }
}
