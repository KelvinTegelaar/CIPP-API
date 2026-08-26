function New-HaloPSATicket {
  [CmdletBinding(SupportsShouldProcess)]
  param (
    $title,
    $description,
    $client,
    [string]$UserUPN,
    [string]$AzureOID,
    [string]$DisplayName,
    [int]$TicketId
  )
  #Get HaloPSA Token based on the config we have.
  $Table = Get-CIPPTable -TableName Extensionsconfig
  $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).HaloPSA
  $TicketTable = Get-CIPPTable -TableName 'PSATickets'
  $token = Get-HaloToken -configuration $Configuration

  # Resolve affected user to a HaloPSA contact when the integration is configured for it.
  # Unmatched users fall through to userlookup.id = -1 (the client's General User contact).
  # An explicit TicketId means the caller already knows which ticket the work belongs to, so there
  # is nothing to resolve - the target ticket carries its own user. This is the case that matters
  # for onboarding: a user created seconds ago is never a HaloPSA contact yet, so matching would
  # always miss and stamp the ticket with the General User fallback.
  $MatchedUser = $null
  $UserLinkActive = $TicketId -le 0 -and $Configuration.LinkTicketsToUsers -and ($UserUPN -or $AzureOID)
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

  # A caller-supplied TicketId targets a ticket CIPP did not open - a scheduled task carrying a PSA
  # reference back to the request it came from - so it bypasses the consolidation table entirely.
  # Otherwise fall back to the ticket CIPP opened for this title, when consolidation is enabled.
  $TargetTicketId = $null
  if ($TicketId -gt 0) {
    $TargetTicketId = $TicketId
    Write-Information "Targeting caller-supplied HaloPSA ticket: $TargetTicketId"
  } elseif ($Configuration.ConsolidateTickets) {
    $ExistingTicket = Get-CIPPAzDataTableEntity @TicketTable -Filter "PartitionKey eq 'HaloPSA' and RowKey eq '$($client)-$($TitleHash)'"
    if ($ExistingTicket) {
      Write-Information "Ticket already exists in HaloPSA: $($ExistingTicket.TicketID)"
      $TargetTicketId = $ExistingTicket.TicketID
    }
  }

  if ($TargetTicketId) {
    $Ticket = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Tickets/$($TargetTicketId)?includedetails=true&includelastaction=false&nocache=undefined&includeusersassets=false&isdetailscreen=true" -ContentType 'application/json; charset=utf-8' -Method Get -Headers @{Authorization = "Bearer $($token.access_token)" } -SkipHttpErrorCheck
    if ($Ticket.id) {
      if (!$Ticket.hasbeenclosed) {
        Write-Information 'Ticket is still open, adding new note'
        # Halo won't take a note without an outcome - it answers "An Outcome must be entered
        # for this Action" - so fall back to 7, the built-in Internal Note outcome, when the
        # integration hasn't been given one. The failure this used to hit was the API user not
        # having rights to the action, which is caught below and falls back to a new ticket so
        # the alert still lands somewhere.
        $Outcome = if ($Configuration.Outcome) {
          $Configuration.Outcome.value ?? $Configuration.Outcome
        } else {
          7
        }
        $Object = [PSCustomObject]@{
          ticket_id      = $TargetTicketId
          outcome_id     = $Outcome
          hiddenfromuser = $true
          note_html      = $description
        }

        $body = ConvertTo-Json -Compress -Depth 10 -InputObject @($Object)
        $NoteAdded = $false
        try {
          if ($PSCmdlet.ShouldProcess('Add note to HaloPSA ticket', 'Add note')) {
            $Action = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/actions" -ContentType 'application/json; charset=utf-8' -Method Post -Body $body -Headers @{Authorization = "Bearer $($token.access_token)" }
            Write-Information "Note added to ticket in HaloPSA: $TargetTicketId"
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
          $OutcomeHint = if ($Configuration.Outcome) {
            "Outcome $Outcome is set for this integration - check the HaloPSA API user can run that action."
          } else {
            "No Outcome is configured, so the built-in Internal Note action ($Outcome) was used. If it has been removed or the API user cannot run it, pick a different Outcome on the HaloPSA integration page."
          }
          Write-LogMessage -message "Failed to add note to HaloPSA ticket $($TargetTicketId): $Message - falling back to creating a new ticket. $OutcomeHint" -API 'HaloPSATicket' -sev Warning -LogData (Get-CippException -Exception $_)
          Write-Information "Failed to add note to HaloPSA ticket: $Message; creating a new ticket instead"
          Write-Information "Body we tried to ship: $body"
        }

        if ($NoteAdded) {
          return "Note added to ticket in HaloPSA: $TargetTicketId"
        }
      }
      else {
        # Falling through to a new ticket keeps the result from being lost, but silently doing so
        # reads as CIPP ignoring the reference, so say which ticket was skipped and why.
        Write-LogMessage -message "HaloPSA ticket $TargetTicketId is closed - the update was raised as a new ticket instead." -API 'HaloPSATicket' -sev Warning
      }
    }
    else {
      Write-Information 'Existing ticket could not be found. Creating a new ticket instead.'
      if ($TicketId -gt 0) {
        Write-LogMessage -message "HaloPSA ticket $TargetTicketId could not be found - the update was raised as a new ticket instead. Check the reference on the scheduled task." -API 'HaloPSATicket' -sev Warning
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
  if ($Configuration.DefaultPriority) {
    $Priority = $Configuration.DefaultPriority.value ?? $Configuration.DefaultPriority
    $PriorityInt = $Priority -as [int]
    if ($PriorityInt -and $PriorityInt -gt 0) {
      $object | Add-Member -MemberType NoteProperty -Name 'priority_id' -Value $PriorityInt -Force
    } else {
      # Stored value isn't a valid Halo priority id (legacy data, hint-row selection, etc.).
      # Skip priority_id rather than crashing the cast - Halo will fall back to its default.
      Write-LogMessage -message "HaloPSA.DefaultPriority value '$Priority' is not a valid integer - omitting priority_id from ticket payload" -API 'HaloPSATicket' -sev Warning
    }
  }
  # Halo records tickets created over the API as 'Manual' unless the payload carries a source, so
  # MSPs who want CIPP's tickets identifiable create their own source in Halo and select it here.
  # Blank keeps the previous behaviour exactly - no source is sent and Halo applies its default.
  $RequestSource = $Configuration.RequestSource.value ?? $Configuration.RequestSource
  if ($null -ne $RequestSource -and "$RequestSource".Trim() -ne '') {
    # Halo source ids include 0 (Email) and negatives (built-in integrations, e.g. -9 Ninja RMM),
    # so presence has to be tested before parsing. The '-gt 0' guard the priority block uses would
    # drop both, and '-as [int]' can't be the guard either - it turns $null and '' into 0, which
    # would silently stamp Email on every install that left this blank.
    $SourceInt = 0
    if ([int]::TryParse("$RequestSource", [ref]$SourceInt)) {
      $object | Add-Member -MemberType NoteProperty -Name 'source' -Value $SourceInt -Force
    } else {
      Write-LogMessage -message "HaloPSA.RequestSource value '$RequestSource' is not a valid integer - omitting source from ticket payload" -API 'HaloPSATicket' -sev Warning
    }
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
