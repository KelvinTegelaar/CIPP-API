function Update-CIPPSharePointLibraryCopyStatus {
    <#
    .SYNOPSIS
        Polls unfinished copy job handles and returns a sanitized operation-level status snapshot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$OperationId
    )

    $CollectIssueMessages = {
        param([array]$HandleStates, [ValidateSet('Error', 'Warning')][string]$Kind)

        $Property = if ($Kind -eq 'Error') { 'ErrorMessages' } else { 'WarningMessages' }
        $Seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $Results = [System.Collections.Generic.List[object]]::new()

        foreach ($State in @($HandleStates)) {
            if ($null -eq $State) { continue }
            foreach ($Message in @($State.$Property)) {
                if ([string]::IsNullOrWhiteSpace($Message)) { continue }
                $Text = [string]$Message
                if ($Seen.Add($Text)) {
                    [void]$Results.Add([PSCustomObject]@{ Severity = $Kind; Message = $Text })
                }
            }
        }

        return @($Results)
    }

    $Operation = Get-CIPPSharePointLibraryCopyOperation -TenantFilter $TenantFilter -OperationId $OperationId
    if (-not $Operation) {
        throw 'Library copy operation not found.'
    }

    if ($Operation.Status -in @('Completed', 'CompletedWithErrors', 'Failed') -and $Operation.SanitizedSnapshot) {
        $Snapshot = $Operation.SanitizedSnapshot
        $Snapshot | Add-Member -NotePropertyName Errors -NotePropertyValue (
            & $CollectIssueMessages -HandleStates $Operation.HandleStates -Kind Error
        ) -Force
        $Snapshot | Add-Member -NotePropertyName Warnings -NotePropertyValue (
            & $CollectIssueMessages -HandleStates $Operation.HandleStates -Kind Warning
        ) -Force
        return $Snapshot
    }

    $JobsTotal = [Math]::Max([int]$Operation.JobHandleCount, @($Operation.CopyJobInfos).Count)
    $HandleStates = @($Operation.HandleStates)
    if ($HandleStates.Count -lt $JobsTotal) {
        $HandleStates = @(1..$JobsTotal | ForEach-Object {
                [PSCustomObject]@{ Status = 'Queued'; IsComplete = $false }
            })
    }

    for ($Index = 0; $Index -lt $JobsTotal; $Index++) {
        $State = $HandleStates[$Index]
        if ($State.IsComplete) { continue }

        try {
            $Progress = Get-CIPPSharePointCopyJobProgress -TenantFilter $TenantFilter `
                -SourceSiteUrl $Operation.SourceSiteUrl -CopyJobInfo $Operation.CopyJobInfos[$Index]
            $HandleStates[$Index] = [PSCustomObject]@{
                Status               = $Progress.Status
                IsComplete           = $Progress.IsComplete
                ObjectsProcessed     = $Progress.ObjectsProcessed
                TotalExpectedObjects = $Progress.TotalExpectedObjects
                FilesCreated         = $Progress.FilesCreated
                BytesProcessed       = $Progress.BytesProcessed
                TotalErrors          = $Progress.TotalErrors
                TotalWarnings        = $Progress.TotalWarnings
                ErrorMessages        = @($Progress.ErrorMessages)
                WarningMessages      = @($Progress.WarningMessages)
            }
        } catch {
            $Detail = [string]$_.Exception.Message
            if ([string]::IsNullOrWhiteSpace($Detail)) {
                $Detail = 'Failed to retrieve copy job progress from SharePoint.'
            } else {
                $Detail = [regex]::Replace($Detail, 'https?://[^\s''"]+', '[url redacted]', 'IgnoreCase')
                $Detail = ($Detail -replace '\s{2,}', ' ').Trim()
                if ($Detail.Length -gt 280) {
                    $Detail = $Detail.Substring(0, 280).Trim() + '…'
                }
            }
            $HandleStates[$Index] = [PSCustomObject]@{
                Status        = 'Failed'
                IsComplete    = $true
                TotalErrors   = 1
                ErrorMessages = @($Detail)
            }
        }
    }

    $JobsComplete = @($HandleStates | Where-Object { $_.IsComplete }).Count
    $ObjectsProcessed = ($HandleStates | ForEach-Object { [int64]($_.ObjectsProcessed ?? 0) } | Measure-Object -Sum).Sum
    $TotalExpected = ($HandleStates | ForEach-Object { $_.TotalExpectedObjects } | Where-Object { $null -ne $_ } | Measure-Object -Sum).Sum
    $FilesCreated = ($HandleStates | ForEach-Object { [int64]($_.FilesCreated ?? 0) } | Measure-Object -Sum).Sum
    $BytesProcessed = ($HandleStates | ForEach-Object { [int64]($_.BytesProcessed ?? 0) } | Measure-Object -Sum).Sum
    $TotalErrors = ($HandleStates | ForEach-Object { [int64]($_.TotalErrors ?? 0) } | Measure-Object -Sum).Sum
    $TotalWarnings = ($HandleStates | ForEach-Object { [int64]($_.TotalWarnings ?? 0) } | Measure-Object -Sum).Sum

    $ProgressPercent = $null
    if ($TotalExpected -gt 0) {
        $ProgressPercent = [Math]::Round(100.0 * $ObjectsProcessed / $TotalExpected, 1)
    } elseif ($JobsTotal -gt 0) {
        $ProgressPercent = [Math]::Round(100.0 * $JobsComplete / $JobsTotal, 1)
    }

    $AnyFailed = @($HandleStates | Where-Object { $_.Status -eq 'Failed' }).Count -gt 0
    $AllComplete = $JobsComplete -ge $JobsTotal

    $Status = if ($AllComplete -and $TotalErrors -gt 0) { 'CompletedWithErrors' }
    elseif ($AllComplete -and -not $AnyFailed) { 'Completed' }
    elseif ($AnyFailed -and $AllComplete) { 'CompletedWithErrors' }
    elseif ($AnyFailed) { 'Failed' }
    else { 'Processing' }

    $Message = switch ($Status) {
        'Completed' { 'Library copy completed.' }
        'CompletedWithErrors' { 'Library copy completed with errors.' }
        'Failed' { 'One or more copy jobs failed.' }
        default { 'Copy in progress.' }
    }

    $Errors = @(& $CollectIssueMessages -HandleStates $HandleStates -Kind Error)
    $Warnings = @(& $CollectIssueMessages -HandleStates $HandleStates -Kind Warning)
    if ($TotalErrors -gt 0 -and $Errors.Count -eq 0) {
        $Errors = @([PSCustomObject]@{
                Severity = 'Error'
                Message  = 'SharePoint reported copy errors, but CIPP could not read detailed messages from the job log or queue.'
            })
    }

    $Snapshot = [PSCustomObject]@{
        OperationId          = $OperationId
        Status               = $Status
        JobsComplete         = $JobsComplete
        JobsTotal            = $JobsTotal
        ObjectsProcessed     = $ObjectsProcessed
        TotalExpectedObjects = if ($TotalExpected -gt 0) { $TotalExpected } else { $null }
        ProgressPercent      = $ProgressPercent
        FilesCreated         = $FilesCreated
        BytesProcessed       = $BytesProcessed
        TotalErrors          = $TotalErrors
        TotalWarnings        = $TotalWarnings
        Errors               = $Errors
        Warnings             = $Warnings
        LastUpdatedUtc       = ([DateTime]::UtcNow).ToString('o')
        Message              = $Message
        SourceSiteName       = $Operation.SourceSiteName
        SourceLibraryName    = $Operation.SourceLibraryName
        DestSiteName         = $Operation.DestSiteName
        DestLibraryName      = $Operation.DestLibraryName
    }

    $Expiry = if ($AllComplete) { ([DateTime]::UtcNow.AddHours(48)).ToString('o') } else { $Operation.Expiry }

    Set-CIPPSharePointLibraryCopyOperation -TenantFilter $TenantFilter -OperationId $OperationId -Entity @{
        SourceSiteUrl     = $Operation.SourceSiteUrl
        SourceSiteName    = $Operation.SourceSiteName
        SourceLibraryName = $Operation.SourceLibraryName
        DestSiteName      = $Operation.DestSiteName
        DestLibraryName   = $Operation.DestLibraryName
        StartedBy         = $Operation.StartedBy
        Status            = $Status
        JobHandleCount    = $JobsTotal
        Expiry            = $Expiry
        HandleStates      = (ConvertTo-Json -InputObject @($HandleStates) -Compress -Depth 6)
        SanitizedSnapshot = (ConvertTo-Json -InputObject $Snapshot -Compress -Depth 6)
    }

    return $Snapshot
}
