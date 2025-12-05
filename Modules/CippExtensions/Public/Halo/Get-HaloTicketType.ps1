function Get-HaloTicketType {
    <#
    .SYNOPSIS
        Get Halo Ticket Type
    .DESCRIPTION
        Get Halo Ticket Type
    .EXAMPLE
        Get-HaloTicketType

    #>
    [CmdletBinding()]
    param ()
    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).HaloPSA
        $Token = Get-HaloToken -configuration $Configuration

        Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/TicketType?showall=true" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" }
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        @(@{name = "Could not get HaloPSA Ticket Types, error: $Message"; id = '' })
    }
}

