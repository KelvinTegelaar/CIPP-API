function Invoke-ExecBECCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Reads, polls or starts a Business Email Compromise investigation.
    .DESCRIPTION
        GET with GUID (or caseId) returns that run: while it is queued or running { Waiting = true, Progress } where Progress is the job status (queued until a worker picks it up, then running) and the per-step state the page renders; { Error, Progress } when it failed; otherwise the results payload with the server-side Score, per-collector Completeness and a Run block. A queued or running run whose progress has not moved for 20 minutes is marked failed by this poll (the worker restarted or the run was abandoned) and returned as { Error }. GET without a GUID returns the user's latest run as { GUID, Status } and starts nothing (GUID is null when the user has no runs). POST with tenantFilter, userid and userName queues a new run and returns its { GUID }. Every run is the full investigation and is kept in the BecReports table; metadata only, never message content.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Payload = $Request.Body
    # Query first, then the body; a query key that is present but empty counts as missing.
    $Pick = { param($FromQuery, $FromBody) if (-not [string]::IsNullOrWhiteSpace([string]$FromQuery)) { $FromQuery } else { $FromBody } }
    $TenantFilter = & $Pick $Request.Query.tenantFilter $Payload.tenantFilter
    # Object id of the user to investigate
    $UserId = [string](& $Pick $Request.Query.userid $Payload.userid)
    # The user's UPN (stored on the run and used by the collectors)
    $UserName = [string](& $Pick $Request.Query.userName $Payload.userName)
    # The run to read; GUID keeps the original poll contract
    $CaseId = [string](& $Pick $Request.Query.GUID $Request.Query.caseId)
    # A POST body with a userid starts a new run
    $Start = -not [string]::IsNullOrWhiteSpace([string]$Payload.userid)
    # A queued/running run with no progress update for this long is abandoned: the worker restarted
    # (Craft retries once, then gives up) or the queue lost it. One audit-log phase can take several
    # minutes on a large tenant, so the threshold is generous.
    $StaleMinutes = 20

    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        if ($CaseId) {
            $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults:$true -ErrorAction Stop
            $Body = if (-not $Run) {
                @{ Waiting = $false; Error = "BEC run $CaseId was not found for $TenantFilter" }
            } elseif ($Run.Status -in @('Waiting', 'Running', 'Error')) {
                # the live progress rows: queued until a worker starts, then one step per phase
                $Progress = try { @(Get-CIPPAsyncDeployment -JobId $Run.CaseId) | Select-Object -First 1 } catch { $null }

                if ($Run.Status -in @('Waiting', 'Running')) {
                    # last sign of life: the job row's last change, else when the run started or was requested
                    $LastActivity = $null
                    foreach ($Candidate in @($Progress.LastUpdate, $Run.StartedAt, $Run.RequestedAt)) {
                        if ($null -eq $Candidate -or "$Candidate" -eq '') { continue }
                        try {
                            $LastActivity = if ($Candidate -is [DateTimeOffset]) { $Candidate.UtcDateTime } else { ([datetime]$Candidate).ToUniversalTime() }
                            break
                        } catch { $LastActivity = $null }
                    }
                    if ($LastActivity -and $LastActivity -lt (Get-Date).ToUniversalTime().AddMinutes(-$StaleMinutes)) {
                        $StaleMessage = "No progress for more than $StaleMinutes minutes - the worker was restarted or the run was abandoned. Start a new run."
                        try {
                            $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $Run.CaseId -Properties @{ Status = 'Error'; ErrorMessage = $StaleMessage; ExtractedAt = (Get-Date).ToUniversalTime().ToString('o') }
                            if ($Progress) {
                                $Steps = @($Progress.Steps)
                                for ($i = 0; $i -lt $Steps.Count; $i++) {
                                    if ($Steps[$i].Status -eq 'running') { Set-CIPPAsyncDeploymentStep -JobId $Run.CaseId -Name $Progress.Name -StepIndex $i -StepStatus 'failed' -Message $StaleMessage; break }
                                }
                                Set-CIPPAsyncDeploymentStatus -JobId $Run.CaseId -Name $Progress.Name -Status 'failed' -Logs $StaleMessage
                                $Progress = try { @(Get-CIPPAsyncDeployment -JobId $Run.CaseId) | Select-Object -First 1 } catch { $Progress }
                            }
                            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC run $($Run.CaseId) marked failed: $StaleMessage" -Sev 'Warning'
                        } catch {
                            Write-Information "BEC: could not mark the stale run $($Run.CaseId) failed: $($_.Exception.Message)"
                        }
                        $Run | Add-Member -NotePropertyName 'Status' -NotePropertyValue 'Error' -Force
                        $Run | Add-Member -NotePropertyName 'ErrorMessage' -NotePropertyValue $StaleMessage -Force
                    }
                }

                $Summary = @{
                    CaseId      = $Run.CaseId
                    Status      = $Run.Status
                    RequestedAt = $Run.RequestedAt
                    RequestedBy = $Run.RequestedBy
                    StartedAt   = $Run.StartedAt
                    Progress    = $Progress
                }
                if ($Run.Status -eq 'Error') {
                    $Summary.Waiting = $false
                    $Summary.Error = ($Run.ErrorMessage ?? 'The BEC run failed')
                } else {
                    $Summary.Waiting = $true
                }
                $Summary
            } else {
                $Results = $Run.Results
                $Results | Add-Member -NotePropertyName 'Run' -NotePropertyValue ([pscustomobject]@{
                        CaseId            = $Run.CaseId
                        Status            = $Run.Status
                        ExtractedAt       = $Run.ExtractedAt
                        RequestedAt       = $Run.RequestedAt
                        RequestedBy       = $Run.RequestedBy
                        Containment       = $Run.Containment
                    }) -Force
                $Results
            }
        } elseif ($Start) {
            if (-not $UserId) { throw 'userid is required' }
            $RequestedBy = try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' }
            # the technician's own address (first x-forwarded-for hop) is never the user's or the attacker's
            $RequestedFromIP = ConvertTo-CIPPBecHostAddress -Address ([string](([string]$Headers.'x-forwarded-for' -split ',')[0])).Trim()
            $Prepared = New-CIPPBecRunRequest -TenantFilter $TenantFilter -UserId $UserId -UserPrincipalName $UserName -RequestedBy ([string]$RequestedBy) -RequestedFromIP ([string]$RequestedFromIP)
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'BECRunOrchestrator'
                Batch            = @($Prepared.Item)
                SkipLog          = $true
            }
            $null = Start-CIPPOrchestrator -InputObject $InputObject
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Queued a BEC investigation for $UserName [case $($Prepared.CaseId)]" -Sev 'Info'
            $Body = @{ GUID = $Prepared.CaseId; CaseId = $Prepared.CaseId; Status = 'Waiting' }
        } else {
            if (-not $UserId) { throw 'userid is required' }
            # the latest run that is not a failure; never starts one
            $Latest = @(Get-CIPPBecReport -TenantFilter $TenantFilter -UserId $UserId | Where-Object { $_.Status -in @('Completed', 'Waiting', 'Running') }) | Select-Object -First 1
            $Body = if ($Latest) {
                @{ GUID = $Latest.CaseId; CaseId = $Latest.CaseId; Status = $Latest.Status }
            } else {
                @{ GUID = $null; CaseId = $null; Status = $null; NoRuns = $true }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC check request failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Waiting = $false; Error = $ErrorMessage.NormalizedError }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
