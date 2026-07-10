function New-HaloPSATicket {
  [CmdletBinding(SupportsShouldProcess)]
  param (
    $title,
    $description,
    $client,
    [string]$UserUPN,
    [string]$AzureOID,
    [string]$DisplayName
  )
  #Get HaloPSA Token based on the config we have.
  $Table = Get-CIPPTable -TableName Extensionsconfig
  $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).HaloPSA
  $TicketTable = Get-CIPPTable -TableName 'PSATickets'
  $token = Get-HaloToken -configuration $Configuration

  # Resolve affected user to a HaloPSA contact when the integration is configured for it.
  # Unmatched users fall through to userlookup.id = -1 (the client's General User contact).
  $MatchedUser = $null
  $UserLinkActive = $Configuration.LinkTicketsToUsers -and ($UserUPN -or $AzureOID)
  if ($UserLinkActive) {
    $MatchedUser = Get-HaloUser -AzureOID $AzureOID -Email $UserUPN -ClientId $client -Configuration $Configuration -Token $token
    if (-not $MatchedUser) {
      $UnmatchedLabel = if ($DisplayName) { "$DisplayName ($UserUPN)" } else { $UserUPN }
      Write-LogMessage -API 'HaloPSATicket' -message "No HaloPSA contact match for $UserUPN in client $client - falling back to General User" -sev Warning
      $description = "$description<p><em>Affected user: $UnmatchedLabel - no matching HaloPSA contact found, ticket assigned to General User.</em></p>"
    }
  }

  # When linking is active, include UPN in the consolidation key so per-user tickets don't
  # collapse onto each other when the same alert title fires for multiple users.
  $HashInput = if ($UserLinkActive -and $UserUPN) { "$title|$UserUPN" } else { $title }
  $TitleHash = Get-StringHash -String $HashInput

  # Halo requires a site_id whenever a specific user is set on the ticket; pull it from the
  # matched user record. When no user is matched, leave site_id null and let Halo resolve it
  # from the General User (id = -1).
  $SiteId = if ($MatchedUser) { $MatchedUser.site_id } else { $null }

  if ($Configuration.ConsolidateTickets) {
    $ExistingTicket = Get-CIPPAzDataTableEntity @TicketTable -Filter "PartitionKey eq 'HaloPSA' and RowKey eq '$($client)-$($TitleHash)'"
    if ($ExistingTicket) {
      Write-Information "Ticket already exists in HaloPSA: $($ExistingTicket.TicketID)"

      $Ticket = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Tickets/$($ExistingTicket.TicketID)?includedetails=true&includelastaction=false&nocache=undefined&includeusersassets=false&isdetailscreen=true" -ContentType 'application/json; charset=utf-8' -Method Get -Headers @{Authorization = "Bearer $($token.access_token)" } -SkipHttpErrorCheck
      if ($Ticket.id) {
        if (!$Ticket.hasbeenclosed) {
          Write-Information 'Ticket is still open, adding new note'
          $Object = [PSCustomObject]@{
            ticket_id      = $ExistingTicket.TicketID
            outcome_id     = 7
            hiddenfromuser = $true
            note_html      = $description
          }
  
          if ($Configuration.Outcome) {
            $Outcome = $Configuration.Outcome.value ?? $Configuration.Outcome
            $Object.outcome_id = $Outcome
          }
  
          $body = ConvertTo-Json -Compress -Depth 10 -InputObject @($Object)
          $NoteAdded = $false
          try {
            if ($PSCmdlet.ShouldProcess('Add note to HaloPSA ticket', 'Add note')) {
              $Action = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/actions" -ContentType 'application/json; charset=utf-8' -Method Post -Body $body -Headers @{Authorization = "Bearer $($token.access_token)" }
              Write-Information "Note added to ticket in HaloPSA: $($ExistingTicket.TicketID)"
              $NoteAdded = $true
            }
          }
          catch {
            $Message = if ($_.ErrorDetails.Message) {
              Get-NormalizedError -Message $_.ErrorDetails.Message
            }
            else {
              $_.Exception.message
            }
            # Don't return here - if appending a note failed (e.g. permissions on the action,
            # invalid outcome_id) we still want to create a fresh ticket so the alert isn't lost.
            Write-LogMessage -message "Failed to add note to HaloPSA ticket $($ExistingTicket.TicketID): $Message - falling back to creating a new ticket" -API 'HaloPSATicket' -sev Warning -LogData (Get-CippException -Exception $_)
            Write-Information "Failed to add note to HaloPSA ticket: $Message; creating a new ticket instead"
            Write-Information "Body we tried to ship: $body"
          }

          if ($NoteAdded) {
            return "Note added to ticket in HaloPSA: $($ExistingTicket.TicketID)"
          }
        }
      }
      else {
        Write-Information 'Existing ticket could not be found. Creating a new ticket instead.'
      }
    }
  }

  $UserLookupId = if ($MatchedUser) { $MatchedUser.id } else { -1 }
  $UserLookupDisplay = if ($MatchedUser) {
    if ($DisplayName) { $DisplayName } else { $UserUPN }
  } else {
    'Enter Details Manually'
  }
  $UserNameValue = if ($MatchedUser) {
    if ($DisplayName) { $DisplayName } else { $UserUPN }
  } else {
    $null
  }

  $Object = [PSCustomObject]@{
    files                      = $null
    usertype                   = 1
    userlookup                 = @{
      id            = $UserLookupId
      lookupdisplay = $UserLookupDisplay
    }
    client_id                  = [int]($client | Select-Object -Last 1)
    _forcereassign             = $true
    site_id                    = $SiteId
    user_name                  = $UserNameValue
    reportedby                 = $null
    summary                    = $title
    details_html               = $description
    donotapplytemplateintheapi = $true
    attachments                = @()
    _novalidate                = $true
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
      return "Ticket created in HaloPSA: $($Ticket.id)"
    }
  }
  catch {
    $Message = if ($_.ErrorDetails.Message) {
      Get-NormalizedError -Message $_.ErrorDetails.Message
    }
    else {
      $_.Exception.message
    }
    Write-LogMessage -message "Failed to send ticket to HaloPSA: $Message" -API 'HaloPSATicket' -sev Error -LogData (Get-CippException -Exception $_)
    Write-Information "Failed to send ticket to HaloPSA: $Message"
    Write-Information "Body we tried to ship: $body"
    return "Failed to send ticket to HaloPSA: $Message"
  }
}
