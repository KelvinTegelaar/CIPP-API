function Get-CIPPSharePointCopyJobProgress {
    <#
    .SYNOPSIS
        Polls GetCopyJobProgress for one handle and returns sanitized aggregate metrics.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$SourceSiteUrl,

        [Parameter(Mandatory = $true)]
        [object]$CopyJobInfo
    )

    $SanitizeCopyLogMessage = {
        param([object]$Entry, [ValidateSet('Error', 'Warning')][string]$Kind)

        $Message = [string]($Entry.Message ?? $Entry.message ?? $Entry.ErrorMessage ?? '')
        $ErrorType = [string]($Entry.ErrorType ?? $Entry.errorType ?? '')
        $ErrorCode = [string]($Entry.ErrorCode ?? $Entry.errorCode ?? '')
        $ObjectType = [string]($Entry.ObjectType ?? $Entry.objectType ?? '')

        if ($ErrorType -match '\.') { $ErrorType = ($ErrorType -split '\.')[-1] }
        if ([string]::IsNullOrWhiteSpace($Message) -and ($ErrorType -or $ErrorCode)) {
            $Message = if ($ErrorCode) { "$ErrorType ($ErrorCode)".Trim(' ()') } else { $ErrorType }
        }
        if ($ObjectType -and $Message) { $Message = "${ObjectType}: $Message" }

        $Fallback = if ($Kind -eq 'Error') { 'SharePoint reported a copy error.' } else { 'SharePoint reported a copy warning.' }
        if ([string]::IsNullOrWhiteSpace($Message)) { return $Fallback }

        $Sanitized = $Message
        $Sanitized = [regex]::Replace($Sanitized, 'https?://[^\s''"]+', '[url redacted]', 'IgnoreCase')
        $Sanitized = [regex]::Replace($Sanitized, '\\[^\s''"]+', '[path redacted]', 'IgnoreCase')
        $Sanitized = [regex]::Replace($Sanitized, '/(?:sites|teams)/[^\s''"]+', '[path redacted]', 'IgnoreCase')
        $Sanitized = [regex]::Replace(
            $Sanitized,
            '[^\s\\/''"]+\.(docx?|xlsx?|pptx?|pdf|txt|csv|png|jpe?g|gif|zip|msg|one|aspx|html?|xml|json|mp4|mov|avi|wmv|rtf|md|svg|webp|heic|tif|tiff|7z|rar|tar|gz|ppt|xls|doc)\b',
            '[file]',
            'IgnoreCase'
        )
        $Sanitized = ($Sanitized -replace '\s{2,}', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($Sanitized)) { return $Fallback }
        return $Sanitized
    }

    $MeasureCopyJobLogs = {
        param([array]$RawLogs = @())

        $ObjectsProcessed = 0
        $TotalExpected = $null
        $FilesCreated = 0
        $BytesProcessed = 0
        $TotalErrors = 0
        $TotalWarnings = 0
        $ErrorMessages = [System.Collections.Generic.List[string]]::new()
        $WarningMessages = [System.Collections.Generic.List[string]]::new()
        $SeenErrors = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $SeenWarnings = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        foreach ($LogLine in @($RawLogs)) {
            $Entry = $LogLine
            if ($LogLine -is [string]) {
                try { $Entry = $LogLine | ConvertFrom-Json } catch { continue }
            }
            if (-not $Entry) { continue }

            $EventName = [string]($Entry.Event ?? $Entry.event ?? $Entry.EventType ?? '')
            $HasErrorDetails = -not [string]::IsNullOrWhiteSpace([string]($Entry.ErrorCode ?? $Entry.errorCode ?? '')) `
                -or -not [string]::IsNullOrWhiteSpace([string]($Entry.ErrorType ?? $Entry.errorType ?? ''))

            switch -Regex ($EventName) {
                'JobError|Error' {
                    $TotalErrors++
                    $SanitizedMessage = & $SanitizeCopyLogMessage -Entry $Entry -Kind Error
                    if ($SeenErrors.Add($SanitizedMessage) -and $ErrorMessages.Count -lt 25) {
                        [void]$ErrorMessages.Add($SanitizedMessage)
                    }
                }
                'JobWarning|Warning' {
                    $TotalWarnings++
                    $SanitizedMessage = & $SanitizeCopyLogMessage -Entry $Entry -Kind Warning
                    if ($SeenWarnings.Add($SanitizedMessage) -and $WarningMessages.Count -lt 25) {
                        [void]$WarningMessages.Add($SanitizedMessage)
                    }
                }
                'JobProgress|JobEnd|JobStart|JobQueued|JobFinishedObjectInfo' {
                    if ($null -ne $Entry.ObjectsProcessed) { $ObjectsProcessed = [int64]$Entry.ObjectsProcessed }
                    if ($null -ne $Entry.TotalExpectedSPObjects) { $TotalExpected = [int64]$Entry.TotalExpectedSPObjects }
                    if ($null -ne $Entry.FilesCreated) { $FilesCreated = [int64]$Entry.FilesCreated }
                    if ($null -ne $Entry.BytesProcessed) { $BytesProcessed = [int64]$Entry.BytesProcessed }
                    if ($null -ne $Entry.TotalErrors) { $TotalErrors = [int64]$Entry.TotalErrors }
                    if ($null -ne $Entry.TotalWarnings) { $TotalWarnings = [int64]$Entry.TotalWarnings }
                }
                default {
                    if ($HasErrorDetails) {
                        $TotalErrors++
                        $SanitizedMessage = & $SanitizeCopyLogMessage -Entry $Entry -Kind Error
                        if ($SeenErrors.Add($SanitizedMessage) -and $ErrorMessages.Count -lt 25) {
                            [void]$ErrorMessages.Add($SanitizedMessage)
                        }
                    }
                }
            }
        }

        if ($TotalErrors -gt 0 -and $ErrorMessages.Count -eq 0) {
            foreach ($LogLine in @($RawLogs)) {
                $Entry = $LogLine
                if ($LogLine -is [string]) {
                    try { $Entry = $LogLine | ConvertFrom-Json } catch { continue }
                }
                if (-not $Entry) { continue }
                if ([string]::IsNullOrWhiteSpace([string]($Entry.Message ?? $Entry.message ?? ''))) { continue }
                $SanitizedMessage = & $SanitizeCopyLogMessage -Entry $Entry -Kind Error
                if ($SeenErrors.Add($SanitizedMessage) -and $ErrorMessages.Count -lt 25) {
                    [void]$ErrorMessages.Add($SanitizedMessage)
                }
            }
        }

        [PSCustomObject]@{
            ObjectsProcessed     = $ObjectsProcessed
            TotalExpectedObjects = $TotalExpected
            FilesCreated         = $FilesCreated
            BytesProcessed       = $BytesProcessed
            TotalErrors          = $TotalErrors
            TotalWarnings        = $TotalWarnings
            ErrorMessages        = @($ErrorMessages)
            WarningMessages      = @($WarningMessages)
        }
    }

    # Accept normalized handles, or legacy OData collection wrappers still in the table.
    $Handle = $CopyJobInfo
    if (-not ($Handle.JobId ?? $Handle.jobId) -and $null -ne $Handle.results) {
        $Handle = @($Handle.results) | Select-Object -First 1
    }

    $JobId = [string]($Handle.JobId ?? $Handle.jobId ?? $Handle.JobID ?? '')
    $JobQueueUri = $Handle.JobQueueUri ?? $Handle.jobQueueUri
    if ($JobQueueUri -is [PSCustomObject]) {
        $JobQueueUri = [string]($JobQueueUri.Url ?? $JobQueueUri.AbsoluteUri ?? $JobQueueUri)
    }
    $JobQueueUri = [string]$JobQueueUri
    $EncryptionKey = $Handle.EncryptionKey ?? $Handle.encryptionKey
    if ($EncryptionKey -is [PSCustomObject]) {
        $EncryptionKey = $EncryptionKey.'#text' ?? $EncryptionKey.Value ?? $EncryptionKey.bytes
    }

    if ([string]::IsNullOrWhiteSpace($JobId) -or [string]::IsNullOrWhiteSpace($JobQueueUri)) {
        throw 'Copy job handle is missing JobId or JobQueueUri.'
    }

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $Scope = "$($SharePointInfo.SharePointUrl)/.default"
    $Uri = "$($SourceSiteUrl.TrimEnd('/'))/_api/site/GetCopyJobProgress"
    $Body = ConvertTo-Json -InputObject @{
        copyJobInfo = @{
            __metadata    = @{ type = 'SP.CopyMigrationInfo' }
            JobQueueUri   = $JobQueueUri
            JobId         = $JobId
            EncryptionKey = $EncryptionKey
        }
    } -Depth 5 -Compress

    $RawLogs = @()
    $JobState = $null
    $RestError = $null

    try {
        $Response = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -scope $Scope -type POST -body $Body `
            -AddedHeaders @{ Accept = 'application/json;odata=verbose' } `
            -contentType 'application/json;odata=verbose' -UseCertificate -AsApp $true

        if ($Response -is [string]) {
            $Response = $Response | ConvertFrom-Json
        }

        $Progress = if ($Response.d.GetCopyJobProgress) {
            $P = $Response.d.GetCopyJobProgress
            if ($P -is [string]) { $P | ConvertFrom-Json } else { $P }
        } elseif ($Response.d) {
            $Response.d
        } else {
            $Response
        }

        $JobState = $Progress.JobState ?? $Progress.jobState
        $LogsProperty = $Progress.Logs ?? $Progress.logs
        if ($null -eq $LogsProperty) {
            $RawLogs = @()
        } elseif ($LogsProperty.PSObject.Properties['results']) {
            $RawLogs = @($LogsProperty.results)
        } elseif ($LogsProperty -is [System.Collections.IEnumerable] -and $LogsProperty -isnot [string]) {
            $RawLogs = @($LogsProperty)
        } else {
            $RawLogs = @($LogsProperty)
        }
    } catch {
        $RestError = $_.Exception.Message
        Write-Information "GetCopyJobProgress REST failed: $RestError"
    }

    $Metrics = & $MeasureCopyJobLogs -RawLogs $RawLogs

    if ($EncryptionKey -and ($RestError -or $Metrics.ErrorMessages.Count -eq 0 -or $RawLogs.Count -eq 0)) {
        try {
            $QueueLogs = Get-CIPPSharePointCopyJobQueueLogs -JobQueueUri $JobQueueUri -EncryptionKey $EncryptionKey
            if ($QueueLogs.Count -gt 0) {
                $Metrics = & $MeasureCopyJobLogs -RawLogs (@($RawLogs) + @($QueueLogs))
            }
        } catch {
            Write-Verbose "SharePoint copy queue log read failed: $($_.Exception.Message)"
        }
    }

    if ($RestError -and $RawLogs.Count -eq 0 -and $Metrics.TotalErrors -eq 0 -and $Metrics.ErrorMessages.Count -eq 0) {
        $Detail = [regex]::Replace([string]$RestError, 'https?://[^\s''"]+', '[url redacted]', 'IgnoreCase')
        $Detail = ($Detail -replace '\s{2,}', ' ').Trim()
        if ($Detail.Length -gt 240) { $Detail = $Detail.Substring(0, 240).Trim() + '…' }
        throw "Failed to retrieve copy job progress from SharePoint: $Detail"
    }

    $StateInt = if ($null -ne $JobState) { [int]$JobState } else { -1 }
    $IsComplete = $StateInt -eq 0
    if (-not $IsComplete -and $StateInt -lt 0 -and (
            $Metrics.TotalErrors -gt 0 -or $Metrics.TotalExpectedObjects -gt 0 -or $Metrics.ObjectsProcessed -gt 0
        )) {
        $IsComplete = $true
    }

    $Status = switch ($true) {
        { $IsComplete -and $Metrics.TotalErrors -gt 0 } { 'CompletedWithErrors' }
        { $IsComplete } { 'Complete' }
        { $StateInt -eq 2 } { 'Queued' }
        default { 'Processing' }
    }

    [PSCustomObject]@{
        Status               = $Status
        JobState             = $StateInt
        IsComplete           = $IsComplete
        ObjectsProcessed     = $Metrics.ObjectsProcessed
        TotalExpectedObjects = $Metrics.TotalExpectedObjects
        FilesCreated         = $Metrics.FilesCreated
        BytesProcessed       = $Metrics.BytesProcessed
        TotalErrors          = $Metrics.TotalErrors
        TotalWarnings        = $Metrics.TotalWarnings
        ErrorMessages        = @($Metrics.ErrorMessages)
        WarningMessages      = @($Metrics.WarningMessages)
    }
}
