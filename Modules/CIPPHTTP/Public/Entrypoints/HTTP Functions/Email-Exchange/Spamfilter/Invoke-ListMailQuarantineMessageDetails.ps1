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

    # Fallback: parse the message headers, then enrich from the exported EML and optional ATP report.
    # Shaped like a partial analyzedEmail object so the frontend can use a single mapping.
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
                $InternetMessageId = & $GetHeader 'Message-ID'

                $Results = @([PSCustomObject]@{
                        recipientEmailAddress = $RecipientAddress
                        internetMessageId     = $InternetMessageId
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

        $FallbackResult = $Results | Select-Object -First 1
        if ($FallbackResult) {
            $EmlBase64 = $null
            try {
                $Metadata.EmlExported = $false
                $ExportResult = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Export-QuarantineMessage' -cmdParams @{ 'Identity' = $Identity }
                $EmlBase64 = [string]$ExportResult.Eml
                if (![string]::IsNullOrWhiteSpace($EmlBase64)) {
                    $Metadata.EmlExported = $true
                }
            } catch {
                $Metadata.EmlExportError = [string](Get-NormalizedError -Message $_.Exception.Message)
            }

            try {
                $Metadata.EmlParsed = $false
                $MaxEmlBytes = 25MB
                if (![string]::IsNullOrWhiteSpace($EmlBase64)) {
                    $EmlBytes = [System.Convert]::FromBase64String($EmlBase64)
                    if ($EmlBytes.Length -le $MaxEmlBytes) {
                        $EmlContent = [System.Text.Encoding]::UTF8.GetString($EmlBytes)
                        $ParsedMime = Read-CippMimeMessage -Message $EmlContent
                        $FallbackResult | Add-Member -NotePropertyName urls -NotePropertyValue @($ParsedMime.urls) -Force
                        $FallbackResult | Add-Member -NotePropertyName attachments -NotePropertyValue @($ParsedMime.attachments) -Force
                        $Metadata.EmlParsed = $true
                    } else {
                        $Metadata.EmlSkipped = "Message export exceeds $([math]::Round($MaxEmlBytes / 1MB)) MB parser limit"
                    }
                }
            } catch {
                $Metadata.EmlParseError = [string](Get-NormalizedError -Message $_.Exception.Message)
            }

            try {
                $Metadata.AtpReport = $false
                $InternetMessageId = [string]$FallbackResult.internetMessageId
                if (![string]::IsNullOrWhiteSpace($InternetMessageId)) {
                    $AtpReceived = $null
                    if (![string]::IsNullOrWhiteSpace($ReceivedTime)) {
                        try { $AtpReceived = ([datetime]$ReceivedTime).ToUniversalTime() } catch { $AtpReceived = $null }
                    }

                    $Now = (Get-Date).ToUniversalTime()
                    if ($AtpReceived) {
                        $AtpStartDate = $AtpReceived.AddDays(-1)
                        $AtpEndDate = $AtpReceived.AddDays(1)
                        if ($AtpEndDate -gt $Now) { $AtpEndDate = $Now }
                    } else {
                        $AtpStartDate = $Now.AddDays(-10)
                        $AtpEndDate = $Now
                    }

                    $AtpParams = @{
                        MessageId = $InternetMessageId
                        StartDate = $AtpStartDate
                        EndDate   = $AtpEndDate
                        PageSize  = 5000
                    }
                    if (![string]::IsNullOrWhiteSpace($RecipientAddress)) {
                        $AtpParams.RecipientAddress = $RecipientAddress
                    }

                    $AtpReport = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailDetailATPReport' -cmdParams $AtpParams | Where-Object { $_ })
                    if (($AtpReport | Measure-Object).Count -gt 0) {
                        $GetAtpValue = {
                            param($ReportEntry, [string[]]$Names)

                            foreach ($Name in $Names) {
                                $Property = $ReportEntry.PSObject.Properties[$Name]
                                if ($Property -and ![string]::IsNullOrWhiteSpace([string]$Property.Value)) {
                                    return [string]$Property.Value
                                }
                            }

                            $null
                        }

                        $AtpDetectionMethods = @($AtpReport | ForEach-Object { & $GetAtpValue $_ @('Event Type', 'EventType') } | Where-Object { $_ } | Select-Object -Unique)
                        $AtpThreatTypes = @($AtpReport | ForEach-Object { & $GetAtpValue $_ @('Verdict Type', 'VerdictType') } | Where-Object { $_ } | Select-Object -Unique)

                        if ($AtpDetectionMethods.Count -gt 0) {
                            $FallbackResult | Add-Member -NotePropertyName detectionMethods -NotePropertyValue $AtpDetectionMethods -Force
                        }
                        if ($AtpThreatTypes.Count -gt 0) {
                            $CombinedThreatTypes = @(@($FallbackResult.threatTypes | Where-Object { $_ }) + @($AtpThreatTypes)) | Select-Object -Unique
                            $FallbackResult | Add-Member -NotePropertyName threatTypes -NotePropertyValue $CombinedThreatTypes -Force
                        }

                        foreach ($AtpEntry in $AtpReport) {
                            $FileName = & $GetAtpValue $AtpEntry @('File Name', 'FileName')
                            $VerdictType = & $GetAtpValue $AtpEntry @('Verdict Type', 'VerdictType')
                            if ([string]::IsNullOrWhiteSpace($FileName) -or [string]::IsNullOrWhiteSpace($VerdictType)) { continue }

                            foreach ($Attachment in @($FallbackResult.attachments)) {
                                if ($Attachment.fileName -eq $FileName) {
                                    $Attachment.threatType = $VerdictType
                                }
                            }
                        }

                        $Metadata.AtpReport = $true
                    }
                }
            } catch {
                $Metadata.AtpError = [string](Get-NormalizedError -Message $_.Exception.Message)
            }
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
