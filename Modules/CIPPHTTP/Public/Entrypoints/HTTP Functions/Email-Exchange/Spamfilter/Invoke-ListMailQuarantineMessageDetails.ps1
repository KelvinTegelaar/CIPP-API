function Invoke-ListMailQuarantineMessageDetails {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Retrieves Defender analyzed email details (threats, delivery, authentication, URLs, attachments)
        for a quarantined message via the Graph beta security/collaboration/analyzedEmails API.
        Falls back to parsing the message headers (Authentication-Results and X-Forefront-Antispam-Report)
        for tenants without Defender for Office 365 Plan 2.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    # Only the quarantine Identity is trusted from the caller. NetworkMessageId, RecipientAddress and
    # ReceivedTime are derived server-side from the quarantine message itself (see below) so this
    # endpoint cannot be used to pull Defender analyzedEmail data for arbitrary, non-quarantined
    # messages in the tenant.
    $Identity = $Request.Query.Identity

    $Results = @()
    $Metadata = @{ Available = $false }

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = @(); Metadata = @{ Available = $false; Message = 'Identity is required' } }
            })
    }

    # Resolve the trusted quarantine message first. Binding the Defender lookup to a message that is
    # actually quarantined for this tenant is what keeps the Exchange.SpamFilter.Read role from being
    # used to investigate messages the operator was never authorized to see.
    try {
        $QuarantineMessage = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams @{ Identity = $Identity }
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = @{ Results = @(); Metadata = @{ Available = $false; Message = [string](Get-NormalizedError -Message $_.Exception.Message) } }
            })
    }

    if (-not $QuarantineMessage -or [string]::IsNullOrWhiteSpace($QuarantineMessage.Identity)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = @{ Results = @(); Metadata = @{ Available = $false; Message = 'Quarantined message not found' } }
            })
    }

    # NetworkMessageId is the first half of the quarantine Identity ({NetworkMessageId}\{RecipientGuid}).
    $NetworkMessageId = [string]($QuarantineMessage.Identity -split '\\')[0]
    $RecipientAddress = @($QuarantineMessage.RecipientAddress)[0]
    $ReceivedTime = $QuarantineMessage.ReceivedTime

    # Primary source: Defender analyzedEmails (requires Defender for Office 365 Plan 2).
    try {
        $MessageGuid = [guid]::Empty
        if (-not [guid]::TryParse($NetworkMessageId, [ref]$MessageGuid)) {
            throw 'NetworkMessageId must be a valid GUID'
        }

        # startTime/endTime are required by the analyzedEmails API. When a received time is supplied,
        # search a +/-1 day window around it; otherwise fall back to the last 15 days.
        $Now = (Get-Date).ToUniversalTime()
        $Received = $null
        if (![string]::IsNullOrWhiteSpace($ReceivedTime)) {
            try { $Received = ([datetime]$ReceivedTime).ToUniversalTime() } catch { $Received = $null }
        }
        if ($Received) {
            $StartDate = $Received.AddDays(-1)
            $EndDate = $Received.AddDays(1)
        } else {
            $StartDate = $Now.AddDays(-15)
            $EndDate = $Now
        }
        if ($EndDate -gt $Now) { $EndDate = $Now }
        $StartTime = $StartDate.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $EndTime = $EndDate.ToString('yyyy-MM-ddTHH:mm:ssZ')

        $Filter = "networkMessageId eq '$($MessageGuid.Guid)'"
        if (![string]::IsNullOrWhiteSpace($RecipientAddress)) {
            $Filter += " and recipientEmailAddress eq '$($RecipientAddress -replace "'", "''")'"
        }
        $EncodedFilter = [System.Uri]::EscapeDataString($Filter)
        $Uri = "https://graph.microsoft.com/beta/security/collaboration/analyzedEmails?startTime=$StartTime&endTime=$EndTime&`$filter=$EncodedFilter"

        $GraphRequest = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true
        if (@($GraphRequest | Where-Object { $_ }).Count -gt 0) {
            $Results = @($GraphRequest)
            $Metadata = @{ Available = $true; Source = 'Defender' }
        }
    } catch {
        # Tenants without Defender for Office 365 Plan 2 get an 'Invalid subscription' error here.
        $DefenderError = [string](Get-NormalizedError -Message $_.Exception.Message)
        $Metadata.Message = $DefenderError
        # A missing SecurityAnalyzedMessage.Read.All grant fails with an authorization error rather
        # than the subscription error above. Flag it so the frontend can prompt to add the missing
        # permission instead of silently presenting the reduced header-only fallback as success.
        if ($DefenderError -match '(?i)Authorization_RequestDenied|forbidden|insufficient privileges|do(es)? not have permission|Access(Is)?Denied') {
            $Metadata.PermissionError = $true
        }
    }

    # Fallback: parse the message headers. Works on every tenant, but only covers authentication
    # results and the anti-spam report (no URLs/attachments). Shaped like a partial analyzedEmail
    # object so the frontend can use a single mapping.
    if ($Results.Count -eq 0 -and ![string]::IsNullOrWhiteSpace($Identity)) {
        try {
            $HeaderResult = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessageHeader' -cmdParams @{ 'Identity' = $Identity }
            $RawHeaders = [string]($HeaderResult.Header ?? $HeaderResult)
            if (![string]::IsNullOrWhiteSpace($RawHeaders)) {
                # Unfold RFC 5322 continuation lines so each header occupies a single line
                $HeaderLines = ($RawHeaders -replace "(?m)\r?\n[ \t]+", ' ') -split "\r?\n"
                $GetHeader = {
                    param($Name)
                    $Pattern = "^(?i)$([regex]::Escape($Name)):\s*"
                    [string](($HeaderLines | Where-Object { $_ -match $Pattern } | Select-Object -First 1) -replace $Pattern, '')
                }

                $Auth = @{}
                $AuthResults = & $GetHeader 'Authentication-Results'
                foreach ($Mechanism in @('spf', 'dkim', 'dmarc', 'compauth')) {
                    if ($AuthResults -match "(?i)\b$Mechanism=([a-z0-9]+)") { $Auth[$Mechanism] = $Matches[1] }
                }

                # X-Forefront-Antispam-Report is a semicolon separated list of KEY:VALUE pairs
                $Report = @{}
                foreach ($Pair in ((& $GetHeader 'X-Forefront-Antispam-Report') -split ';')) {
                    $Key, $Value = $Pair -split ':', 2
                    if ($Key -and $Value) { $Report[$Key.Trim()] = $Value.Trim() }
                }

                # https://learn.microsoft.com/defender-office-365/message-headers-eop-mdo
                $CategoryNames = @{
                    AMP = 'Anti-malware'; BULK = 'Bulk'; DIMP = 'Domain impersonation'; FTBP = 'Common attachment filter'
                    GIMP = 'Mailbox intelligence impersonation'; HPHISH = 'High confidence phishing'; HPHSH = 'High confidence phishing'
                    HSPM = 'High confidence spam'; INTOS = 'Intra-organization phishing'; MALW = 'Malware'; OSPM = 'Outbound spam'
                    PHSH = 'Phishing'; SAP = 'Safe Attachments'; SPM = 'Spam'; SPOOF = 'Spoofing'; UIMP = 'User impersonation'
                }
                $DirectionNames = @{ INB = 'Inbound'; OUT = 'Outbound'; INT = 'Intra-org' }

                $FromHeader = & $GetHeader 'From'
                $SenderDisplayName = if ($FromHeader -match '^\s*"?([^"<]*?)"?\s*<') { $Matches[1].Trim() } else { $null }
                $Category = $CategoryNames[$Report['CAT']] ?? $Report['CAT']

                $Results = @([PSCustomObject]@{
                        recipientEmailAddress = $RecipientAddress
                        internetMessageId     = & $GetHeader 'Message-ID'
                        returnPath            = ((& $GetHeader 'Return-Path') -replace '[<>]', '').Trim()
                        directionality        = $DirectionNames[$Report['DIR']] ?? $Report['DIR']
                        language              = $Report['LANG']
                        spamConfidenceLevel   = $Report['SCL']
                        bulkComplaintLevel    = $Report['BCL']
                        threatTypes           = @($Category | Where-Object { $_ })
                        senderDetail          = [PSCustomObject]@{
                            displayName = $SenderDisplayName
                            ipv4        = $Report['CIP']
                            location    = $Report['CTRY']
                        }
                        authenticationDetails = [PSCustomObject]@{
                            dmarc                   = $Auth['dmarc']
                            dkim                    = $Auth['dkim']
                            senderPolicyFramework   = $Auth['spf']
                            compositeAuthentication = $Auth['compauth']
                        }
                    })
                $Metadata.Available = $true
                $Metadata.Source = 'Headers'
            }
        } catch {
            $HeaderError = [string](Get-NormalizedError -Message $_.Exception.Message)
            $Metadata.Message = @($Metadata.Message, $HeaderError) -ne $null -join ' | '
        }
    }

    $Body = @{
        Results  = $Results
        Metadata = $Metadata
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
