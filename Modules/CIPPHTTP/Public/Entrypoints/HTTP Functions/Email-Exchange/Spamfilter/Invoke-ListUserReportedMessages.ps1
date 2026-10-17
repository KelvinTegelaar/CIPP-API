function Invoke-ListUserReportedMessages {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Lists user reported messages (Outlook Report button) for a tenant. Source=AuditLog (default) reads the unified
        audit log two weeks per page, Source=Submissions reads the Defender Submissions list from Graph.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # AuditLog (default) or Submissions
    $Source = $Request.Query.Source

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $GraphRequest = @()
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'User reported messages are loaded per tenant. Select a tenant to view its reported messages.'
            }
        } elseif ($Source -eq 'Submissions') {
            # Defender Submissions via Graph: only what reached Microsoft analysis, Outlook reports mostly show up once an
            # admin submits them (source 'administrator')
            $Submissions = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/threatSubmission/emailThreats' -tenantid $TenantFilter -AsApp $true
            $Results = [System.Collections.Generic.List[object]]::new()
            foreach ($Submission in $Submissions) {
                $Results.Add([PSCustomObject]@{
                        ReportedDateTime  = $Submission.createdDateTime
                        ReceivedDateTime  = $Submission.receivedDateTime
                        Subject           = $Submission.subject ?? $Submission.emailSubject
                        Sender            = $Submission.sender
                        SenderIP          = $Submission.senderIP
                        RecipientEmail    = $Submission.recipientEmailAddress
                        # Graph returns createdBy flat ({ id, displayName, email }), the docs sample nests it under 'user'
                        ReportedBy        = $Submission.createdBy.displayName ?? $Submission.createdBy.user.displayName ?? $Submission.createdBy.email ?? $Submission.createdBy.user.email
                        ReporterEmail     = $Submission.createdBy.email ?? $Submission.createdBy.user.email
                        Source            = $Submission.source
                        Category          = $Submission.category
                        OriginalCategory  = $Submission.originalCategory
                        Status            = $Submission.status
                        ResultCategory    = $Submission.result.category
                        ResultDetail      = $Submission.result.detail
                        AdminReviewResult = $Submission.adminReview.reviewResult
                        InternetMessageId = $Submission.internetMessageId
                        Id                = $Submission.id
                        Tenant            = $TenantFilter
                    })
            }
            $GraphRequest = $Results | Sort-Object -Property ReportedDateTime -Descending
        } else {
            # Graph's threatSubmission list skips Outlook Report button submissions, the unified audit log has them all.
            # One two-week window per call, Metadata.nextLink points at the previous window so the table pages back
            # until the audit log's 180-day standard retention.
            # ponytail: plain searches capped at 5000 rows (no ReturnLargeSet session, that timed out at ~100s on a real
            # tenant). A capped window is halved until it fits. Move to a cached DB job if this becomes more than a demo
            $WindowDays = 14
            $Now = (Get-Date).ToUniversalTime()
            $Oldest = $Now.AddDays(-180)
            $EndDate = if ($Request.Query.nextLink) { ([datetime]::Parse($Request.Query.nextLink, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)) } else { $Now }
            $StartDate = $EndDate.AddDays(-$WindowDays)
            if ($StartDate -lt $Oldest) { $StartDate = $Oldest }

            $ResultSize = 5000
            # A capped search drops rows, so halve the window toward EndDate until it fits. The next page then starts at the
            # narrowed StartDate, nothing between the windows is skipped. Below an hour it stays capped and says so.
            do {
                $SearchParams = @{
                    StartDate  = $StartDate
                    EndDate    = $EndDate
                    RecordType = 'MailSubmission'
                    Operations = @('UserSubmission', 'CustomSubmission', 'AttackSimUserSubmission')
                    ResultSize = $ResultSize
                }
                # A search with no hits returns nothing, not an empty array
                $Records = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Search-UnifiedAuditLog' -cmdParams $SearchParams | Where-Object { $_.AuditData })
                $Capped = $Records.Count -ge $ResultSize
                $CanSplit = ($EndDate - $StartDate).TotalHours -gt 1
                if ($Capped -and $CanSplit) { $StartDate = $StartDate.AddTicks([long](($EndDate - $StartDate).Ticks / 2)) }
            } while ($Capped -and $CanSplit)
            # Audit timestamps are UTC without an offset (ConvertFrom-Json makes them Unspecified datetimes), stamp them as UTC
            $AsUtc = { param($Value) if ($Value -is [datetime]) { [datetime]::SpecifyKind($Value, 'Utc').ToString('o') } elseif ($Value) { "$($Value)Z" } }
            $Results = [System.Collections.Generic.List[object]]::new()
            # A reported phish simulation logs both UserSubmission and AttackSimUserSubmission for the same submission,
            # keep one row per submission and prefer the simulation record
            $Seen = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Record in ($Records | Sort-Object { $_.Operations -ne 'AttackSimUserSubmission' })) {
                $Data = try { $Record.AuditData | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                if (-not $Data) { continue }
                if (-not $Seen.Add([string]($Data.SubmissionId ?? $Data.Id))) { continue }
                $Results.Add([PSCustomObject]@{
                        ReportedDateTime  = & $AsUtc ($Data.CreationTime ?? $Record.CreationDate)
                        ReceivedDateTime  = & $AsUtc $Data.MessageDate
                        Subject           = $Data.Subject
                        Sender            = $Data.P2Sender ?? $Data.P1Sender
                        SenderIP          = $Data.SenderIP
                        RecipientEmail    = @($Data.Recipients) -join ', '
                        ReportedBy        = $Data.UserId
                        ReporterEmail     = $Data.UserId
                        Source            = $Data.Operation
                        # SubmissionType is an undocumented number (0/1 seen), shown raw for the demo
                        Category          = "$($Data.SubmissionType)"
                        OriginalCategory  = ($Data.ExtendedProperties | Where-Object Name -EQ 'OriginalVerdict').Value
                        Status            = $Data.SubmissionState
                        ResultCategory    = $Data.RescanResult.RescanVerdict ?? ($Data.ExtendedProperties | Where-Object Name -EQ 'RescanVerdict').Value
                        ResultDetail      = $Data.DeliveryMessageInfo.FinalFilterVerdict
                        AdminReviewResult = $null
                        InternetMessageId = $Data.InternetMessageId
                        Id                = $Data.SubmissionId ?? $Data.Id
                        Tenant            = $TenantFilter
                    })
            }
            $GraphRequest = $Results | Sort-Object -Property ReportedDateTime -Descending
            $Metadata = [PSCustomObject]@{
                WindowStart = $StartDate.ToString('o')
                WindowEnd   = $EndDate.ToString('o')
                Complete    = -not $Capped
            }
            if ($Capped) {
                $Metadata | Add-Member -NotePropertyName Warning -NotePropertyValue "More than $ResultSize reports between $($StartDate.ToString('u')) and $($EndDate.ToString('u')), only the first $ResultSize are listed."
            }
            if ($StartDate -gt $Oldest) { $Metadata | Add-Member -NotePropertyName nextLink -NotePropertyValue $StartDate.ToString('o') }
        }
        $Body = [PSCustomObject]@{
            Results  = @($GraphRequest)
            Metadata = $Metadata
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
