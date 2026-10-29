function New-NinjaOneTicket {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Raises a ticket in NinjaOne Ticketing for a mapped organisation, or comments on the open ticket CIPP already raised for the same title.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        $Title,
        $Description,
        # NinjaOne organisation id from the NinjaOne tenant mapping.
        $Client,
        [string]$UserUPN,
        [string]$AzureOID,
        [string]$DisplayName,
        # Per-alert override. Only a NinjaOne priority name (NONE/LOW/MEDIUM/HIGH) is honoured; the
        # alert form stores HaloPSA priority ids in the same field and those are ignored here.
        $TicketPriority,
        [int]$TicketId,
        [string]$ConsolidationKey,
        # CIPP tenant customerId, used to read the NinjaOne device map written by the tenant sync.
        [string]$TenantCustomerId,
        # Device to attach to the ticket: EntraDeviceId (Entra deviceId) and/or IntuneId (managed device
        # id) and/or SerialNumber, plus DisplayName.
        $AffectedDevice
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json).NinjaOne
    $TicketTable = Get-CIPPTable -TableName 'PSATickets'
    # Ticket writes are refused for the app-only token, so they run as the technician who connected.
    $Token = Get-NinjaOneUserToken -Configuration $Configuration
    if (-not $Token.access_token) {
        $Message = 'Failed to send ticket to NinjaOne: ticketing is not connected. Use Connect on the NinjaOne integration page to sign in.'
        Write-LogMessage -message $Message -API 'NinjaOneTicket' -sev Error
        return $Message
    }
    $BaseUri = "https://$($Configuration.Instance -replace '/ws', '' -replace 'https://', '')/api/v2/ticketing"
    $Headers = @{ Authorization = "Bearer $($Token.access_token)" }

    $FormId = ($Configuration.TicketForm.value ?? $Configuration.TicketForm) -as [int]
    if (-not $FormId) {
        $Message = 'Failed to send ticket to NinjaOne: no Ticket Form is selected on the NinjaOne integration page.'
        Write-LogMessage -message $Message -API 'NinjaOneTicket' -sev Error
        return $Message
    }

    # Same rules as HaloPSA: a caller-supplied ticket already has its requester, and linking
    # splits consolidation per user so two people's alerts never share one ticket.
    $MatchedUser = $null
    $UserLinkActive = $TicketId -le 0 -and $Configuration.LinkTicketsToUsers -and $UserUPN
    if ($UserLinkActive) {
        $MatchedUser = Get-NinjaOneTicketUser -Emails @($UserUPN) -ClientId $Client -Configuration $Configuration -Token $Token
        if (-not $MatchedUser) {
            $UnmatchedLabel = if ($DisplayName) { "$DisplayName ($UserUPN)" } else { $UserUPN }
            Write-LogMessage -API 'NinjaOneTicket' -message "No NinjaOne end user or contact with email $UserUPN in organisation $Client - ticket raised without a requester" -sev Warning
            $Description = "$Description<p><em>Affected user: $UnmatchedLabel - no matching NinjaOne end user found, ticket raised without a requester.</em></p>"
        }
    }

    $HashBase = if ([string]::IsNullOrWhiteSpace($ConsolidationKey)) { $Title } else { $ConsolidationKey }
    $HashInput = if ($UserLinkActive) { "$HashBase|$UserUPN" } else { $HashBase }
    $TitleHash = Get-StringHash -String $HashInput
    $RowKey = "$($Client)-$($TitleHash)"

    # Same precedence as HaloPSA: a caller-supplied ticket beats the consolidation table.
    $TargetTicketId = $null
    if ($TicketId -gt 0) {
        $TargetTicketId = $TicketId
    } elseif ($Configuration.ConsolidateTickets) {
        $ExistingTicket = Get-CIPPAzDataTableEntity @TicketTable -Filter "PartitionKey eq 'NinjaOne' and RowKey eq '$RowKey'"
        if ($ExistingTicket) {
            Write-Information "Ticket already exists in NinjaOne: $($ExistingTicket.TicketID)"
            $TargetTicketId = $ExistingTicket.TicketID
        }
    }

    if ($TargetTicketId) {
        $Ticket = try {
            Invoke-RestMethod -Uri "$BaseUri/ticket/$TargetTicketId" -Method GET -Headers $Headers -ContentType 'application/json'
        } catch {
            Write-Information "NinjaOne ticket $TargetTicketId could not be read: $($_.Exception.Message)"
            $null
        }
        # Resolved (5000) and Closed (6000) are NinjaOne's terminal system statuses; custom statuses
        # carry one of them as parentId.
        $Closed = $Ticket.status.name -in @('RESOLVED', 'CLOSED') -or $Ticket.status.parentId -in @(5000, 6000)
        if ($Ticket.id -and -not $Closed) {
            $Comment = @{ public = $false; htmlBody = "$Description"; body = (ConvertTo-NinjaOnePlainText -Html $Description) }
            try {
                if ($PSCmdlet.ShouldProcess("NinjaOne ticket $TargetTicketId", 'Add comment')) {
                    # The comment endpoint only takes multipart with the comment as a JSON part.
                    $Form = [System.Net.Http.MultipartFormDataContent]::new()
                    $Form.Add([System.Net.Http.StringContent]::new(($Comment | ConvertTo-Json -Compress), [System.Text.Encoding]::UTF8, 'application/json'), 'comment')
                    $null = Invoke-RestMethod -Uri "$BaseUri/ticket/$TargetTicketId/comment" -Method POST -Headers $Headers -Body $Form
                    Write-Information "Comment added to NinjaOne ticket $TargetTicketId"
                    return "Comment added to NinjaOne ticket: $TargetTicketId"
                }
            } catch {
                $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
                Write-LogMessage -message "Failed to add comment to NinjaOne ticket $($TargetTicketId): $Message - raising a new ticket instead." -API 'NinjaOneTicket' -sev Warning -LogData (Get-CippException -Exception $_)
            }
        } elseif ($Ticket.id) {
            Write-LogMessage -message "NinjaOne ticket $TargetTicketId is $($Ticket.status.displayName ?? $Ticket.status.name) - the update was raised as a new ticket instead." -API 'NinjaOneTicket' -sev Warning
        } elseif ($TicketId -gt 0) {
            Write-LogMessage -message "NinjaOne ticket $TargetTicketId could not be found - the update was raised as a new ticket instead." -API 'NinjaOneTicket' -sev Warning
        }
    }

    $Status = "$($Configuration.TicketStatus.value ?? $Configuration.TicketStatus)".Trim()
    if (-not $Status) { $Status = '1000' }

    $Body = [ordered]@{
        clientId     = [int]($Client | Select-Object -Last 1)
        ticketFormId = $FormId
        subject      = "$Title"
        status       = $Status
        description  = @{
            public   = $false
            htmlBody = "$Description"
            body     = (ConvertTo-NinjaOnePlainText -Html $Description)
        }
    }

    if ($MatchedUser) { $Body.requesterUid = $MatchedUser.uid }

    # Device link: the tenant sync's NinjaOneDeviceMap first (RowKey is the Entra deviceId, M365ID the
    # Intune id, NinjaOneID the node), then the organisation's devices by serial number for devices
    # the sync has not mapped yet.
    $NodeId = $null
    if ($AffectedDevice) {
        if ($TenantCustomerId -and ($AffectedDevice.EntraDeviceId -or $AffectedDevice.IntuneId)) {
            $DeviceMapTable = Get-CIPPTable -TableName 'NinjaOneDeviceMap'
            $MapFilter = if ($AffectedDevice.EntraDeviceId) {
                "PartitionKey eq '$TenantCustomerId' and RowKey eq '$($AffectedDevice.EntraDeviceId)'"
            } else {
                "PartitionKey eq '$TenantCustomerId' and M365ID eq '$($AffectedDevice.IntuneId)'"
            }
            $Mapped = Get-CIPPAzDataTableEntity @DeviceMapTable -Filter $MapFilter
            if ($Mapped.NinjaOneID) { $NodeId = [int]($Mapped.NinjaOneID | Select-Object -First 1) }
        }
        if (-not $NodeId -and $AffectedDevice.SerialNumber) {
            $Serial = "$($AffectedDevice.SerialNumber)" -replace '\s', ''
            try {
                $OrgDevices = @(Invoke-RestMethod -Uri "$($BaseUri -replace '/ticketing$', '')/devices-detailed?pageSize=1000&df=org = $([int]$Client)" -Method GET -Headers $Headers -ContentType 'application/json')
                $Found = $OrgDevices | Where-Object { (("$($_.system.serialNumber)" -replace '\s', '') -ieq $Serial) -or (("$($_.system.biosSerialNumber)" -replace '\s', '') -ieq $Serial) } | Select-Object -First 1
                if ($Found.id) { $NodeId = [int]$Found.id }
            } catch {
                Write-Information "NinjaOne device lookup by serial failed: $($_.Exception.Message)"
            }
        }
        if ($NodeId) {
            $Body.nodeId = $NodeId
        } else {
            $DeviceLabel = $AffectedDevice.DisplayName ?? $AffectedDevice.SerialNumber ?? $AffectedDevice.IntuneId ?? $AffectedDevice.EntraDeviceId
            Write-LogMessage -API 'NinjaOneTicket' -message "No NinjaOne device matched '$DeviceLabel' in organisation $Client - ticket raised without a device" -sev Warning
        }
    }

    $Priority = $null
    foreach ($Candidate in @(($TicketPriority.value ?? $TicketPriority), ($Configuration.TicketPriority.value ?? $Configuration.TicketPriority))) {
        $Name = "$Candidate".Trim().ToUpperInvariant()
        if ($Name -in @('NONE', 'LOW', 'MEDIUM', 'HIGH')) { $Priority = $Name; break }
    }
    if ($Priority) { $Body.priority = $Priority }

    $Json = ConvertTo-Json -Compress -Depth 10 -InputObject $Body
    Write-Information "Sending ticket to NinjaOne: $Json"
    try {
        if ($PSCmdlet.ShouldProcess('NinjaOne', 'Create ticket')) {
            $Created = Invoke-RestMethod -Uri "$BaseUri/ticket" -Method POST -Headers $Headers -ContentType 'application/json; charset=utf-8' -Body $Json
            Write-Information "Ticket created in NinjaOne: $($Created.id)"
            if ($Configuration.ConsolidateTickets) {
                $TicketObject = [PSCustomObject]@{
                    PartitionKey = 'NinjaOne'
                    RowKey       = $RowKey
                    Title        = "$Title"
                    ClientId     = "$Client"
                    TicketID     = $Created.id
                }
                Add-CIPPAzDataTableEntity @TicketTable -Entity $TicketObject -Force
            }
            return "Ticket created in NinjaOne: $($Created.id)"
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-LogMessage -message "Failed to send ticket to NinjaOne: $Message" -API 'NinjaOneTicket' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information "Body we tried to ship: $Json"
        return "Failed to send ticket to NinjaOne: $Message"
    }
}

function ConvertTo-NinjaOnePlainText {
    # NinjaOne wants a text body beside the HTML one; alert bodies are HTML fragments.
    param([string]$Html)
    [System.Net.WebUtility]::HtmlDecode(([regex]::Replace("$Html", '<[^>]+>', ' ') -replace '\s+', ' ')).Trim()
}
