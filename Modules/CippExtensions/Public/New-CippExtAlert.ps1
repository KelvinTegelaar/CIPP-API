function New-CippExtAlert {
    [CmdletBinding()]
    param (
        [switch]$TestRun = $false,
        [pscustomobject]$Alert
    )
    #Get the current CIPP Alerts table and see what system is configured to receive alerts
    $Table = Get-CIPPTable -TableName Extensionsconfig
    $Configuration = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10 -ErrorAction SilentlyContinue
    $MappingTable = Get-CIPPTable -TableName CippMapping

    foreach ($ConfigItem in $Configuration.psobject.properties.name) {
        switch ($ConfigItem) {
            'HaloPSA' {
                if ($Configuration.HaloPSA.enabled) {
                    $MappingFile = Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq 'HaloMapping'"
                    $TenantId = (Get-Tenants -TenantFilter $Alert.TenantId).customerId
                    $MappedId = ($MappingFile | Where-Object { $_.RowKey -eq $TenantId }).IntegrationId
                    if (!$MappedId) {
                        # Unmapped tenants land on client 1; say so instead of doing it silently.
                        $MappedId = 1
                        Write-LogMessage -API 'HaloPSATicket' -tenant $Alert.TenantId -message "No HaloPSA client mapping for tenant $($Alert.TenantId) - the ticket was raised against Halo client id 1. Map the tenant under Settings > Integrations > HaloPSA." -sev Warning
                    }
                    Write-Information "HaloPSA client for tenant $($Alert.TenantId): $MappedId"

                    $TicketParams = @{
                        Title       = $Alert.AlertTitle
                        Description = $Alert.AlertText
                        Client      = $MappedId
                    }

                    # A task can name the ticket the work came from, so the PSA copy lands as a note
                    # on that ticket instead of opening a second one. Two sources, in order:
                    #
                    #   PsaTicketId  - the ticket box on the user/offboarding/scheduler forms, shown
                    #                  only when this integration is enabled. Unambiguous, so it wins.
                    #   Reference    - free text, and only an [ID:nnnn] token in it counts. That is
                    #                  HaloPSA's own subject token, which is also what makes the
                    #                  emailed copy thread onto the same ticket. A bare number is
                    #                  deliberately NOT accepted: the reference legitimately holds
                    #                  order numbers, asset tags and change ids, and treating one as
                    #                  a ticket id would append a starter's password to an unrelated
                    #                  ticket.
                    #
                    # Reading both is this extension's job: the formats are Halo's, and the scheduler
                    # passes the values through untouched.
                    $ReferencedTicketId = 0
                    $TicketCandidate = if ($Alert.PsaTicketId) {
                        "$($Alert.PsaTicketId)".Trim()
                    } elseif ("$($Alert.Reference)" -match '\[ID:(\d+)\]') {
                        $Matches[1]
                    } else {
                        $null
                    }
                    if ($TicketCandidate) {
                        # TryParse rather than a cast: a long run of digits is a valid match but an
                        # invalid ticket id, and an overflow here would cost the alert entirely.
                        $ParsedTicketId = 0
                        if ([int]::TryParse($TicketCandidate, [ref]$ParsedTicketId) -and $ParsedTicketId -gt 0) {
                            $ReferencedTicketId = $ParsedTicketId
                            $TicketParams.TicketId = $ReferencedTicketId
                            Write-Information "Alert targets HaloPSA ticket $ReferencedTicketId - adding a note to it instead of creating a ticket"
                            # Setting both and disagreeing is easy to do by accident, and the effect is
                            # confusing: the reference is what the notification title shows, so the note
                            # lands on a ticket the title never mentions and it looks like nothing
                            # happened. Say where it actually went.
                            if ($Alert.PsaTicketId -and "$($Alert.Reference)" -match '\[ID:(\d+)\]' -and $Matches[1] -ne "$ReferencedTicketId") {
                                Write-LogMessage -API 'HaloPSATicket' -tenant $Alert.TenantId -message "Task targets HaloPSA ticket $ReferencedTicketId from its ticket field, but its reference names ticket $($Matches[1]). The note was added to $ReferencedTicketId." -sev Warning
                            }
                        } else {
                            Write-LogMessage -API 'HaloPSATicket' -tenant $Alert.TenantId -message "'$TicketCandidate' is not a usable HaloPSA ticket id - raising a new ticket instead." -sev Warning
                        }
                    }

                    # A referenced ticket already carries its own end user, so skip the contact lookup
                    # (and the Graph call under it) entirely.
                    if ($ReferencedTicketId -le 0 -and $Alert.AffectedUser -and $Configuration.HaloPSA.LinkTicketsToUsers) {
                        $UPN = $Alert.AffectedUser.UPN
                        $OID = $Alert.AffectedUser.AzureOID
                        $Display = $Alert.AffectedUser.DisplayName

                        # Best-effort: resolve UPN -> Azure Object ID via Graph if we don't already have it.
                        # Failure here is non-fatal; Get-HaloUser will still try the email-based lookup.
                        if (-not $OID -and $UPN -and $Alert.TenantId) {
                            try {
                                $EncodedUPN = [System.Uri]::EscapeDataString($UPN)
                                $GraphUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$EncodedUPN`?`$select=id,displayName,userPrincipalName" -tenantid $Alert.TenantId -AsApp $true
                                if ($GraphUser.id) { $OID = $GraphUser.id }
                                if (-not $Display -and $GraphUser.displayName) { $Display = $GraphUser.displayName }
                            } catch {
                                Write-Information "Could not resolve Graph user for $UPN in tenant $($Alert.TenantId): $($_.Exception.Message)"
                            }
                        }

                        if ($UPN) { $TicketParams.UserUPN = $UPN }
                        if ($OID) { $TicketParams.AzureOID = $OID }
                        if ($Display) { $TicketParams.DisplayName = $Display }
                    }

                    # Per-alert priority beats the integration-wide DefaultPriority. Unlike the
                    # user fields above this is NOT gated on LinkTicketsToUsers - priority applies
                    # to every ticket, and it must also work when no global default is configured.
                    if ($Alert.PsaTicketPriority) {
                        $TicketParams.TicketPriority = $Alert.PsaTicketPriority
                    }

                    New-HaloPSATicket @TicketParams
                }
            }
            'Gradient' {
                if ($Configuration.Gradient.enabled) {
                    New-GradientAlert -Title $Alert.AlertTitle -Description $Alert.AlertText -Client $Alert.TenantId
                }
            }
        }
    }

}
