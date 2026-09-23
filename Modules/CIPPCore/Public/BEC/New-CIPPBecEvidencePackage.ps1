function New-CIPPBecEvidencePackage {
    <#
    .SYNOPSIS
        Builds the evidence package (ZIP) for a BEC run.
    .DESCRIPTION
        Collates everything CIPP holds about a case into one ZIP: the results payload as JSON, one
        CSV per finding set, the score, the containment history, every logbook line stamped with the
        case id, and the browser-rendered PDF reports when supplied. Nothing is stored: the ZIP is
        returned to the caller to hand to the browser. Everything inside is metadata the run already
        collected; passwords were redacted before they were stored and are scrubbed from the logbook
        copy again here.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER CaseId
        The run to package.
    .PARAMETER PdfBase64
        Optional base64-encoded full PDF report rendered by the frontend.
    .PARAMETER PdfSummaryBase64
        Optional base64-encoded C-suite summary PDF rendered by the frontend.
    .PARAMETER Headers
        CIPP request headers, for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [string]$PdfBase64,
        [string]$PdfSummaryBase64,
        $Headers,
        [string]$APIName = 'BECEvidenceExport'
    )

    $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults
    if (-not $Run) { throw "BEC run $CaseId was not found for $TenantFilter" }
    if ($Run.Status -ne 'Completed') { throw "BEC run $CaseId is $($Run.Status); only completed runs can be exported" }
    $Results = $Run.Results
    $GeneratedUtc = (Get-Date).ToUniversalTime()
    $Utf8 = [System.Text.UTF8Encoding]::new($false)

    # Flatten a row for CSV: arrays join, nested objects become compact JSON.
    $Flatten = {
        param($Row)
        $Out = [ordered]@{}
        foreach ($Property in $Row.PSObject.Properties) {
            $Value = $Property.Value
            $Out[$Property.Name] = if ($null -eq $Value) { '' }
            elseif ($Value -is [string] -or $Value -is [ValueType]) { $Value }
            elseif ($Value -is [System.Collections.IEnumerable]) { @($Value | ForEach-Object { if ($_ -is [string] -or $_ -is [ValueType]) { $_ } else { ConvertTo-Json -InputObject $_ -Compress -Depth 5 } }) -join '; ' }
            else { ConvertTo-Json -InputObject $Value -Compress -Depth 5 }
        }
        [pscustomobject]$Out
    }

    $Files = [ordered]@{}
    $Files['results.json'] = $Utf8.GetBytes((ConvertTo-Json -InputObject $Results -Depth 20))
    $CsvSections = @('NewRules', 'InboxRuleChanges', 'MailboxPermissionChanges', 'SentMessages', 'SafelistChanges', 'SharingChanges', 'SuspectUserSignIns', 'SuspectUserDevices', 'NewUsers', 'ChangedPasswords', 'MFADevices', 'IntuneDevices', 'AddedApps', 'MaliciousSPs', 'Delegations', 'MailboxAddIns', 'UserGrants', 'TransportRuleChanges', 'TransportRulesFlagged', 'ReceivedMailFindings', 'DefenderDetections', 'DirectoryAudits', 'RegisteredDevices', 'NonInteractiveSignIns', 'MailActivity')
    foreach ($Section in $CsvSections) {
        $Rows = @($Results.$Section | Where-Object { $_ -and $_ -isnot [string] })
        if ($Rows.Count -eq 0) { continue }
        $Csv = @($Rows | ForEach-Object { & $Flatten $_ } | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
        $Files["findings/$Section.csv"] = $Utf8.GetBytes($Csv)
    }
    if ($Results.RiskState -and @($Results.RiskState.Detections).Count -gt 0) {
        $Files['findings/RiskDetections.csv'] = $Utf8.GetBytes((@($Results.RiskState.Detections | ForEach-Object { & $Flatten $_ } | ConvertTo-Csv -NoTypeInformation) -join "`r`n"))
    }
    if ($Results.Score) { $Files['score.json'] = $Utf8.GetBytes((ConvertTo-Json -InputObject $Results.Score -Depth 10)) }
    $Files['containment.json'] = $Utf8.GetBytes((ConvertTo-Json -InputObject @($Run.Containment | Where-Object { $_ }) -Depth 15))

    # Logbook: every line stamped with the case id, across the day partitions the case spans.
    $LogRows = @()
    try {
        $From = try { ([datetime]($Run.RequestedAt ?? $Run.ExtractedAt)).ToUniversalTime().AddDays(-1) } catch { $GeneratedUtc.AddDays(-30) }
        if ($From -lt $GeneratedUtc.AddDays(-60)) { $From = $GeneratedUtc.AddDays(-60) }
        $LogTable = Get-CIPPTable -TableName 'CippLogs'
        $Filter = "BecCaseId eq '$($CaseId -replace "'", "''")' and PartitionKey ge '$($From.ToString('yyyyMMdd'))' and PartitionKey le '$($GeneratedUtc.AddDays(1).ToString('yyyyMMdd'))'"
        $LogRows = @(Get-CIPPAzDataTableEntity @LogTable -Filter $Filter | Where-Object { $_ } | Sort-Object -Property Timestamp | ForEach-Object {
                $LogData = [string]$_.LogData
                # belt and braces: a copyField (password) never leaves the system through the package
                $LogData = [regex]::Replace($LogData, '"copyField"\s*:\s*"[^"]*"', '"copyField":"[redacted]"')
                [pscustomobject]@{
                    Timestamp = $_.Timestamp
                    Tenant    = $_.Tenant
                    API       = $_.API
                    Severity  = $_.Severity
                    Username  = $_.Username
                    Message   = $_.Message
                    LogData   = $LogData
                    RowKey    = $_.RowKey
                }
            })
    } catch {
        Write-Information "BEC evidence: logbook query failed for $CaseId`: $($_.Exception.Message)"
    }
    $Files['logbook.json'] = $Utf8.GetBytes((ConvertTo-Json -InputObject @($LogRows) -Depth 10))

    # The frontend renders the reports client-side (react-pdf), so it hands the PDFs in. Validate and
    # add each supplied one - the full report and the C-suite summary.
    $AddPdf = {
        param([string]$Base64, [string]$Name)
        if ([string]::IsNullOrWhiteSpace($Base64)) { return }
        $PdfBytes = [System.Convert]::FromBase64String(($Base64 -replace '^data:application/pdf;base64,', ''))
        if ($PdfBytes.Length -gt 25MB) { throw "The PDF report ($Name) exceeds 25 MB" }
        if ($PdfBytes.Length -lt 4 -or [System.Text.Encoding]::ASCII.GetString($PdfBytes, 0, 4) -ne '%PDF') { throw "The supplied $Name report is not a PDF" }
        $Files[$Name] = $PdfBytes
    }
    & $AddPdf $PdfBase64 'report-full.pdf'
    & $AddPdf $PdfSummaryBase64 'report-summary.pdf'

    $Stream = [System.IO.MemoryStream]::new()
    $Archive = [System.IO.Compression.ZipArchive]::new($Stream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($Name in $Files.Keys) {
            $Entry = $Archive.CreateEntry($Name, [System.IO.Compression.CompressionLevel]::Optimal)
            $EntryStream = $Entry.Open()
            try { $EntryStream.Write($Files[$Name], 0, $Files[$Name].Length) } finally { $EntryStream.Dispose() }
        }
    } finally {
        $Archive.Dispose()
    }
    $ZipBytes = $Stream.ToArray()
    $Stream.Dispose()

    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Exported the evidence package for BEC case $CaseId ($($Files.Count) files, $([math]::Round($ZipBytes.Length / 1KB)) KB); the package was handed to the requester and not stored" -Sev 'Info'

    return [pscustomobject]@{
        CaseId    = $CaseId
        Bytes     = $ZipBytes.Length
        FileCount = $Files.Count
        ZipBytes  = $ZipBytes
    }
}
