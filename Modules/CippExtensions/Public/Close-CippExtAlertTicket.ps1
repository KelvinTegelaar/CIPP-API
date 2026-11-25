function Close-CippExtAlertTicket {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Closes the consolidated PSA ticket an alert task raised once the alert has cleared.
    .DESCRIPTION
        Called after an alert run that completed with nothing left open. Only the ticket CIPP raised and keeps in
        the PSATickets consolidation table is touched, and only for integrations with CloseResolvedTickets on.
        The run that resolves the last items marks the ticket; the next clean run closes it, so a single empty
        or flapping run never closes a ticket. A ticket someone already closed is left alone. Failures are logged
        and retried on the next clean run, and never reach the alert run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$ConsolidationKey,
        [string]$AlertName,
        [int]$ResolvedCount
    )

    try {
        $ConfigTable = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = (Get-CIPPAzDataTableEntity @ConfigTable).config | ConvertFrom-Json -ErrorAction Stop
        $Providers = @(
            if ($Configuration.HaloPSA.Enabled -and $Configuration.HaloPSA.ConsolidateTickets -and $Configuration.HaloPSA.CloseResolvedTickets) { 'HaloPSA' }
            if ($Configuration.NinjaOne.Enabled -and $Configuration.NinjaOne.TicketingEnabled -and $Configuration.NinjaOne.ConsolidateTickets -and $Configuration.NinjaOne.CloseResolvedTickets) { 'NinjaOne' }
        )
        if ($Providers.Count -eq 0) { return }
        $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $MappingTable = Get-CIPPTable -TableName CippMapping
        $TicketTable = Get-CIPPTable -TableName PSATickets
        $KeyHash = Get-StringHash -String $ConsolidationKey
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not check whether the PSA ticket for alert '$AlertName' can be closed: $($_.Exception.Message)" -sev Warning
        return
    }

    $Note = '<p>CIPP: the alert condition for {0} has cleared, so this ticket was closed automatically.</p>' -f [System.Net.WebUtility]::HtmlEncode($AlertName)
    foreach ($Provider in $Providers) {
        $TicketId = $null
        try {
            $MappingPartition = if ($Provider -eq 'HaloPSA') { 'HaloMapping' } else { 'NinjaOneMapping' }
            $Client = (Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq '$MappingPartition' and RowKey eq '$TenantId'").IntegrationId
            # Same client New-CippExtAlert raised the ticket under: unmapped tenants land on Halo client 1.
            if (-not $Client) {
                if ($Provider -ne 'HaloPSA') { continue }
                $Client = 1
            }
            $Row = Get-CIPPAzDataTableEntity @TicketTable -Filter "PartitionKey eq '$Provider' and RowKey eq '$($Client)-$($KeyHash)'"
            if (-not $Row.TicketID) { continue }
            $TicketId = $Row.TicketID

            if ($ResolvedCount -gt 0) {
                $null = Update-CIPPAzDataTableEntity @TicketTable -Entity @{ PartitionKey = $Provider; RowKey = [string]$Row.RowKey; ClearRuns = 1 }
                continue
            }
            if ([int]$Row.ClearRuns -lt 1) { continue }

            if ($Provider -eq 'HaloPSA') {
                $Halo = $Configuration.HaloPSA
                $Outcome = $Halo.CloseOutcome.value ?? $Halo.CloseOutcome
                if (-not $Outcome) { throw 'no Close Outcome is selected on the HaloPSA integration page.' }
                $Token = Get-HaloToken -configuration $Halo
                $Headers = @{ Authorization = "Bearer $($Token.access_token)" }
                $UserAgent = Get-CippUserAgent
                $Ticket = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Halo.ResourceURL)/Tickets/$TicketId" -Method Get -Headers $Headers -ContentType 'application/json'
                $AlreadyClosed = [bool]$Ticket.hasbeenclosed
                if (-not $AlreadyClosed) {
                    # sendemail false: a closing outcome usually carries an email template, and Halo rejects the action without a recipient.
                    $Body = ConvertTo-Json -Compress -InputObject @([PSCustomObject]@{ ticket_id = $TicketId; outcome_id = $Outcome; hiddenfromuser = $true; sendemail = $false; note_html = $Note })
                    $null = Invoke-RestMethod -UserAgent $UserAgent -Uri "$($Halo.ResourceURL)/actions" -Method Post -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $Body
                }
            } else {
                $Token = Get-NinjaOneUserToken
                if (-not $Token.access_token) { throw 'ticketing is not connected. Use Connect on the NinjaOne integration page to sign in.' }
                $BaseUri = "https://$($Configuration.NinjaOne.Instance -replace '/ws', '' -replace 'https://', '')/api/v2/ticketing"
                $Headers = @{ Authorization = "Bearer $($Token.access_token)" }
                $Ticket = Invoke-RestMethod -Uri "$BaseUri/ticket/$TicketId" -Method GET -Headers $Headers -ContentType 'application/json'
                $AlreadyClosed = $Ticket.status.name -in @('RESOLVED', 'CLOSED') -or $Ticket.status.parentId -in @(5000, 6000)
                if (-not $AlreadyClosed) {
                    $Comment = @{ public = $false; htmlBody = $Note; body = (ConvertTo-NinjaOnePlainText -Html $Note) }
                    $Form = [System.Net.Http.MultipartFormDataContent]::new()
                    $Form.Add([System.Net.Http.StringContent]::new(($Comment | ConvertTo-Json -Compress), [System.Text.Encoding]::UTF8, 'application/json'), 'comment')
                    $null = Invoke-RestMethod -Uri "$BaseUri/ticket/$TicketId/comment" -Method POST -Headers $Headers -Body $Form
                    # The update replaces the ticket, so it carries the ticket's own fields with only the status changed to Resolved.
                    $Update = @{ status = '5000' }
                    foreach ($Field in 'version', 'clientId', 'ticketFormId', 'locationId', 'nodeId', 'subject', 'type', 'assignedAppUserId', 'requesterUid', 'severity', 'priority', 'parentTicketId', 'tags') {
                        if ($null -ne $Ticket.$Field) { $Update[$Field] = $Ticket.$Field }
                    }
                    $null = Invoke-RestMethod -Uri "$BaseUri/ticket/$TicketId" -Method PUT -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body (ConvertTo-Json -Compress -Depth 5 -InputObject $Update)
                }
            }

            $null = Remove-CIPPAzDataTableEntity @TicketTable -Entity $Row -Force
            $Message = if ($AlreadyClosed) {
                "$Provider ticket $TicketId for alert '$AlertName' was already closed, so CIPP left it alone."
            } else {
                "Closed $Provider ticket $($TicketId): the alert '$AlertName' has cleared."
            }
            Write-LogMessage -API "$($Provider)Ticket" -tenant $TenantFilter -message $Message -sev Info
        } catch {
            $ErrorMessage = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
            Write-LogMessage -API "$($Provider)Ticket" -tenant $TenantFilter -message "Could not close $Provider ticket $TicketId after the alert '$AlertName' cleared: $("$ErrorMessage".TrimEnd('.')). CIPP will try again on the next run." -sev Warning -LogData (Get-CippException -Exception $_)
        }
    }
}
