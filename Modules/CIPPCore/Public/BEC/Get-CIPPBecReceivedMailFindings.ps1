function Get-CIPPBecReceivedMailFindings {
    <#
    .SYNOPSIS
        Finds phishing-shaped mail the investigated user received, from message-trace and Defender metadata.
    .DESCRIPTION
        Walks the message trace for mail delivered to the user and applies two heuristics to the
        metadata: named phishing-subject patterns (urgency, account verification, suspension, prizes,
        invoices) and look-alike sender domains within Levenshtein distance 1-2 of one of the tenant's
        accepted domains. Where Defender for Office 365 Plan 2 is licensed it also reads the
        analysedEmails metadata for the recipient (sender, subject, verdict, delivery action) and keeps
        the rows Defender classified as a threat. Nothing here touches message bodies or attachments;
        every field comes from trace or analysis metadata.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The recipient.
    .PARAMETER StartDate
        Window start (UTC).
    .PARAMETER EndDate
        Window end (UTC).
    .PARAMETER Heuristics
        The BEC heuristics object.
    .PARAMETER AcceptedDomains
        The tenant's accepted domains (protected domains for the typosquat check).
    .PARAMETER Anchor
        Anchor mailbox for the EXO requests.
    .PARAMETER IncludeDefender
        Also query Defender analysedEmails metadata.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate,
        [Parameter(Mandatory = $true)]$Heuristics,
        [string[]]$AcceptedDomains = @(),
        [string]$Anchor,
        [switch]$IncludeDefender
    )

    $MinDistance = [int]($Heuristics.typosquat.minDistance ?? 1)
    $MaxDistance = [int]($Heuristics.typosquat.maxDistance ?? 2)
    $Patterns = @{}
    if ($Heuristics.phishingSubjectPatterns) {
        foreach ($Property in $Heuristics.phishingSubjectPatterns.PSObject.Properties) { $Patterns[$Property.Name] = [string]$Property.Value }
    }
    $KeywordPattern = [string]$Heuristics.phishingKeywordPattern
    $Accepted = @($AcceptedDomains | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)

    # Every received message's subject by internet message id, so the attacker-activity pass can name
    # the messages the attacker opened without tracing them again (kept in memory, not stored).
    $MessageIndex = @{}
    $Findings = try {
        $Trace = Get-CIPPBecMessageTrace -TenantFilter $TenantFilter -RecipientAddress $UserPrincipalName -StartDate $StartDate -EndDate $EndDate -Anchor $Anchor
        $Rows = @($Trace.Rows)
        foreach ($Row in $Rows) { if ($Row.MessageId -and -not $MessageIndex.ContainsKey([string]$Row.MessageId)) { $MessageIndex[[string]$Row.MessageId] = [string]$Row.Subject } }

        # Typosquat is a property of the sender domain, so evaluate each distinct domain once.
        $DomainVerdicts = @{}
        foreach ($Domain in @($Rows | ForEach-Object { ([string]$_.SenderAddress -split '@')[-1].Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)) {
            if ($Domain -in $Accepted) { continue }
            foreach ($Protected in $Accepted) {
                $Distance = Get-CIPPLevenshteinDistance -Source $Domain -Target $Protected
                if ($Distance -ge $MinDistance -and $Distance -le $MaxDistance) {
                    $DomainVerdicts[$Domain] = [pscustomobject]@{ ComparedDomain = $Protected; Distance = $Distance }
                    break
                }
            }
        }

        $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $List = [System.Collections.Generic.List[object]]::new()
        $Add = {
            param($Row, $Type, $Severity, $Reason, $Compared, $Distance)
            $Key = "$Type|$($Row.MessageTraceId)|$($Row.SenderAddress)|$Reason"
            if (-not $Seen.Add($Key)) { return }
            $List.Add([pscustomobject]@{
                    FindingType    = $Type
                    Severity       = $Severity
                    Reason         = $Reason
                    ComparedDomain = $Compared
                    Distance       = $Distance
                    SenderAddress  = $Row.SenderAddress
                    SenderDomain   = ([string]$Row.SenderAddress -split '@')[-1]
                    Subject        = $Row.Subject
                    Received       = if ($Row.Received) { try { ([datetime]$Row.Received).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } catch { [string]$Row.Received } } else { $null }
                    Status         = $Row.Status
                    Size           = $Row.Size
                    FromIP         = $Row.FromIP
                    MessageTraceId = $Row.MessageTraceId
                })
        }
        foreach ($Row in $Rows) {
            $Subject = [string]$Row.Subject
            $Domain = ([string]$Row.SenderAddress -split '@')[-1].Trim().ToLowerInvariant()
            if ($DomainVerdicts.ContainsKey($Domain)) {
                & $Add $Row 'PossibleTyposquat' 'ReviewHigh' "Sender domain is $($DomainVerdicts[$Domain].Distance) edit(s) from $($DomainVerdicts[$Domain].ComparedDomain)" $DomainVerdicts[$Domain].ComparedDomain $DomainVerdicts[$Domain].Distance
            }
            foreach ($Name in $Patterns.Keys) {
                if ($Patterns[$Name] -and $Subject -match $Patterns[$Name]) { & $Add $Row 'SubjectPattern' 'Review' $Name $null $null }
            }
            if ($KeywordPattern -and $Subject -match $KeywordPattern -and -not ($Patterns.Values | Where-Object { $_ -and $Subject -match $_ })) {
                & $Add $Row 'SubjectKeyword' 'Low' 'Subject contains a common phishing keyword' $null $null
            }
        }

        $Summary = [pscustomobject]@{
            TotalMessages    = @($Rows.MessageTraceId | Select-Object -Unique).Count
            TotalRows        = $Rows.Count
            UniqueSenders    = @($Rows.SenderAddress | Where-Object { $_ } | Select-Object -Unique).Count
            TopSenderDomains = @($Rows | Where-Object { $_.SenderAddress } | Group-Object -Property { ([string]$_.SenderAddress -split '@')[-1].ToLowerInvariant() } | Sort-Object -Property Count -Descending | Select-Object -First 10 | ForEach-Object { [pscustomobject]@{ Domain = $_.Name; Count = $_.Count } })
            TyposquatDomains = @($DomainVerdicts.Keys)
        }
        $Result = New-CIPPBecCollectorResult -Data @($List | Sort-Object -Property @{ Expression = { $_.Severity -eq 'ReviewHigh' }; Descending = $true }, @{ Expression = { $_.Received }; Descending = $true }) -Complete $Trace.Complete -Cap $Trace.Cap
        $Result | Add-Member -NotePropertyName 'Summary' -NotePropertyValue $Summary -Force
        $Result
    } catch {
        $Result = New-CIPPBecCollectorResult -Data @() -Error "Received message trace failed: $((Get-NormalizedError -message $_.Exception.Message))"
        $Result | Add-Member -NotePropertyName 'Summary' -NotePropertyValue $null -Force
        $Result
    }

    $Defender = if ($IncludeDefender) {
        try {
            $Now = (Get-Date).ToUniversalTime()
            $End = if ($EndDate.ToUniversalTime() -gt $Now) { $Now } else { $EndDate.ToUniversalTime() }
            # The service rejects $filter on recipientEmailAddress ("Invalid filter with propName"), so the whole
            # window is read tenant-wide (metadata only) and matched to the mailbox here. The pages are streamed
            # through the match, so only this mailbox's rows are ever held however busy the tenant is.
            $Uri = "https://graph.microsoft.com/beta/security/collaboration/analyzedEmails?startTime=$($StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))&endTime=$($End.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$top=1000"
            $Analyzed = @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -Stream | Where-Object { $_ -and ([string]$_.recipientEmailAddress -eq $UserPrincipalName -or (@($_.recipientDetail.ccRecipients) -contains $UserPrincipalName)) })
            $Threats = foreach ($Mail in $Analyzed) {
                $ThreatTypes = @($Mail.threatTypes | Where-Object { $_ -and $_ -notin @('none', 'unknown', 'unknownFutureValue') })
                if ($ThreatTypes.Count -eq 0) { continue }
                $Action = [string]($Mail.latestDelivery.action ?? $Mail.deliveryAction)
                $LatestLocation = [string]($Mail.latestDelivery.location ?? $Mail.latestDeliveryLocation)
                [pscustomobject]@{
                    NetworkMessageId         = $Mail.networkMessageId
                    ReceivedDateTime         = $Mail.loggedDateTime ?? $Mail.receivedDateTime
                    SenderAddress            = $Mail.senderDetail.fromAddress ?? $Mail.senderDetail.mailFromAddress ?? $Mail.p2Sender ?? $Mail.p1Sender
                    SenderIP                 = $Mail.senderDetail.ipv4 ?? $Mail.senderDetail.ipv6 ?? $Mail.senderDetail.senderIPv4 ?? $Mail.senderDetail.senderIPv6
                    Subject                  = $Mail.subject
                    ThreatTypes              = $ThreatTypes
                    DetectionMethods         = @($Mail.detectionMethods ?? $Mail.threatDetectionDetails)
                    DeliveryAction           = $Action
                    OriginalDeliveryLocation = $Mail.originalDelivery.location ?? $Mail.originalDeliveryLocation
                    LatestDeliveryLocation   = $LatestLocation
                    PhishConfidenceLevel     = $Mail.phishConfidenceLevel
                    Delivered                = ($Action -match '^(delivered|deliveredAsSpam|replaced|deliveredToJunk)$' -or $LatestLocation -match '^(inbox|junkFolder|folder)')
                }
            }
            $Result = New-CIPPBecCollectorResult -Data @($Threats | Sort-Object -Property @{ Expression = { $_.Delivered }; Descending = $true }, @{ Expression = { $_.ReceivedDateTime }; Descending = $true })
            $Result | Add-Member -NotePropertyName 'AnalyzedCount' -NotePropertyValue $Analyzed.Count -Force
            $Result | Add-Member -NotePropertyName 'Available' -NotePropertyValue $true -Force
            $Result
        } catch {
            $Message = [string](Get-NormalizedError -message $_.Exception.Message)
            $IsPermission = [bool]($Message -match '(?i)Authorization_RequestDenied|forbidden|insufficient privileges|do(es)? not have permission|Access(Is)?Denied')
            $IsLicense = [bool]($Message -match '(?i)subscription|licen[cs]e|not enabled|Defender')
            # A missing licence or permission is a skipped check (couldn't run), not a failure.
            $Requirement = if ($IsLicense) { 'requires Defender for Office 365 Plan 2' } elseif ($IsPermission) { 'requires the Defender threat-hunting read permission' } else { $null }
            $Result = New-CIPPBecCollectorResult -Data @() -Error "Defender analysed-email metadata unavailable: $Message" -Skipped ([bool]($IsLicense -or $IsPermission)) -Requirement $Requirement
            $Result | Add-Member -NotePropertyName 'Available' -NotePropertyValue $false -Force
            $Result | Add-Member -NotePropertyName 'PermissionError' -NotePropertyValue $IsPermission -Force
            $Result | Add-Member -NotePropertyName 'LicenseError' -NotePropertyValue $IsLicense -Force
            $Result
        }
    } else {
        # Defender was not queried (the run's licence preflight found no Defender for Office 365 Plan 2):
        # a skipped check, not a clean pass.
        $Result = New-CIPPBecCollectorResult -Data @() -Skipped $true -Requirement 'requires Defender for Office 365 Plan 2'
        $Result | Add-Member -NotePropertyName 'Available' -NotePropertyValue $false -Force
        $Result
    }

    return [pscustomobject]@{
        Findings     = $Findings
        Defender     = $Defender
        MessageIndex = $MessageIndex
    }
}
