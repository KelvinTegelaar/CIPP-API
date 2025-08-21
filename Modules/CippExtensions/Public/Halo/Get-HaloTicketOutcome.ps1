function Get-HaloTicketOutcome {
  <#
    .SYNOPSIS
        Get Halo Ticket Outcome
    .DESCRIPTION
        Get Halo Ticket Outcome
    .EXAMPLE
        Get-HaloTicketOutcome

    #>
  [CmdletBinding()]
  param ()
  $Table = Get-CIPPTable -TableName Extensionsconfig
  try {
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).HaloPSA
    $Token = Get-HaloToken -configuration $Configuration
    $TicketType = $Configuration.TicketType.value ?? $Configuration.TicketType
    if ($TicketType) {
      $WorkflowId = (Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/tickettype/$TicketType" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" }).workflow_id
      $Workflow = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/workflow/$WorkflowId" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" }
      $Outcomes = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/outcome" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" }
      $Outcomes | Where-Object { $_.id -in $Workflow.steps.actions.action_id } | Sort-Object -Property buttonname
    }
    else {
      # Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/outcome" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($Token.access_token)" }
      @(
        @{
          buttonname = 'Select and save a Ticket Type first to see available outcomes'
          value      = -1
        }
      )
    }
  }
  catch {
    $Message = if ($_.ErrorDetails.Message) {
      Get-NormalizedError -Message $_.ErrorDetails.Message
    }
    else {
      $_.Exception.message
    }
    @(@{name = "Could not get HaloPSA Outcomes, error: $Message"; id = '' })
  }
}

