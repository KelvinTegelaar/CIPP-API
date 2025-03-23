function New-HaloPSATicket {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        $title,
        $description,
        $client
    )
    #Get Halo PSA Token based on the config we have.
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).HaloPSA
    $TicketTable = Get-CIPPTable -TableName 'PSATickets'
    $token = Get-HaloToken -configuration $Configuration
    # sha hash title
    $TitleHash = Get-StringHash -String $title

    if ($Configuration.ConsolidateTickets) {
        $ExistingTicket = Get-CIPPAzDataTableEntity @TicketTable -Filter "PartitionKey eq 'HaloPSA' and RowKey eq '$($client)-$($TitleHash)'"
        if ($ExistingTicket) {
            Write-Information "Ticket already exists in HaloPSA: $($ExistingTicket.TicketID)"

            $Ticket = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Tickets/$($ExistingTicket.TicketID)?includedetails=true&includelastaction=false&nocache=undefined&includeusersassets=false&isdetailscreen=true" -ContentType 'application/json; charset=utf-8' -Method Get -Headers @{Authorization = "Bearer $($token.access_token)" }
            if (!$Ticket.hasbeenclosed) {
                Write-Information 'Ticket is still open, adding new note'
                $Object = [PSCustomObject]@{
                    ticket_id      = $ExistingTicket.TicketID
                    outcome        = 'Private Note'
                    outcome_id     = 7
                    hiddenfromuser = $true
                    note_html      = $description
                }
                $body = ConvertTo-Json -Compress -Depth 10 -InputObject @($Object)
                try {
                    if ($PSCmdlet.ShouldProcess('Add note to HaloPSA ticket', 'Add note')) {
                        $Action = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/actions" -ContentType 'application/json; charset=utf-8' -Method Post -Body $body -Headers @{Authorization = "Bearer $($token.access_token)" }
                        Write-Information "Note added to ticket in HaloPSA: $($Action.id)"
                    }
                    return
                } catch {
                    $Message = if ($_.ErrorDetails.Message) {
                        Get-NormalizedError -Message $_.ErrorDetails.Message
                    } else {
                        $_.Exception.message
                    }
                    Write-LogMessage -message "Failed to add note to HaloPSA ticket: $Message" -API 'HaloPSATicket' -sev Error -LogData (Get-CippException -Exception $_)
                    Write-Information "Failed to add note to HaloPSA ticket: $Message"
                    Write-Information "Body we tried to ship: $body"
                    return
                }
            }
        }
    }

    $Object = [PSCustomObject]@{
        files                      = $null
        usertype                   = 1
        userlookup                 = @{
            id            = -1
            lookupdisplay = 'Enter Details Manually'
        }
        client_id                  = ($client | Select-Object -Last 1)
        _forcereassign             = $true
        site_id                    = $null
        user_name                  = $null
        reportedby                 = $null
        summary                    = $title
        details_html               = $description
        donotapplytemplateintheapi = $true
        attachments                = @()
    }

    if ($Configuration.TicketType) {
        $TicketType = $Configuration.TicketType.value ?? $Configuration.TicketType
        $object | Add-Member -MemberType NoteProperty -Name 'tickettype_id' -Value $TicketType -Force
    }
    #use the token to create a new ticket in HaloPSA
    $body = ConvertTo-Json -Compress -Depth 10 -InputObject @($Object)

    Write-Information 'Sending ticket to HaloPSA'
    Write-Information $body
    try {
        if ($PSCmdlet.ShouldProcess('Send ticket to HaloPSA', 'Create ticket')) {
            $Ticket = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Tickets" -ContentType 'application/json; charset=utf-8' -Method Post -Body $body -Headers @{Authorization = "Bearer $($token.access_token)" }
            Write-Information "Ticket created in HaloPSA: $($Ticket.id)"

            if ($Configuration.ConsolidateTickets) {
                $TicketObject = [PSCustomObject]@{
                    PartitionKey = 'HaloPSA'
                    RowKey       = "$($client)-$($TitleHash)"
                    Title        = $title
                    ClientId     = $client
                    TicketID     = $Ticket.id
                }
                Add-CIPPAzDataTableEntity @TicketTable -Entity $TicketObject -Force
                Write-Information 'Ticket added to consolidation table'
            }
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }
        Write-LogMessage -message "Failed to send ticket to HaloPSA: $Message" -API 'HaloPSATicket' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information "Failed to send ticket to HaloPSA: $Message"
        Write-Information "Body we tried to ship: $body"
    }
}
