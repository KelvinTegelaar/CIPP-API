function Invoke-ExecNHICheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .SYNOPSIS
        Reads, polls or starts a non-human identity (NHI) compromise investigation of an app or managed identity.
    .DESCRIPTION
        GET with caseId returns that run: while it is queued or running { Waiting = true, Progress } with the per-step state the page renders; { Error, Progress } when it failed; otherwise the results payload with the server-side Score, per-collector Completeness and a Run block. GET with servicePrincipalId and no caseId returns that app's latest run as { CaseId, Status } and starts nothing. POST with tenantFilter and servicePrincipalId (or servicePrincipalIds for several apps) queues a new run per app and returns { CaseId } (or { Cases }). Runs are kept in the NhiReports table; metadata only, never message or file content.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Payload = $Request.Body
    $TenantFilter = $Request.Query.tenantFilter ?? $Payload.tenantFilter
    # The run to read
    $CaseId = [string]($Request.Query.caseId ?? $Payload.caseId)
    # Object id of the service principal to investigate
    $ServicePrincipalId = [string]($Request.Query.servicePrincipalId ?? $Payload.servicePrincipalId)
    # Object ids of several service principals to investigate, one run each
    $ServicePrincipalIds = @(@($Payload.servicePrincipalIds) + @($Payload.servicePrincipalId) | ForEach-Object { [string]($_.value ?? $_) } | Where-Object { $_ } | Select-Object -Unique)
    # A body naming an app starts a run
    $Start = $ServicePrincipalIds.Count -gt 0

    try {
        $StatusCode = [HttpStatusCode]::OK
        if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { throw [System.ArgumentException]::new('tenantFilter must be a single tenant') }
        $ParsedId = [guid]::Empty
        foreach ($Id in @($ServicePrincipalIds) + @($ServicePrincipalId | Where-Object { $_ })) {
            if (-not [guid]::TryParse($Id, [ref]$ParsedId)) { throw [System.ArgumentException]::new("servicePrincipalId must be a GUID: $Id") }
        }
        if ($CaseId) {
            $Run = Get-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults -ErrorAction Stop
            if (-not $Run) { throw [System.Management.Automation.ItemNotFoundException]::new("NHI run $CaseId was not found for $TenantFilter") }
            $Body = if ($Run.Status -in @('Waiting', 'Running', 'Error')) {
                $Progress = try { @(Get-CIPPAsyncDeployment -JobId $Run.CaseId) | Select-Object -First 1 } catch { $null }
                $Status = [string]$Run.Status
                $RunError = $Run.ErrorMessage
                # a phase killed by a worker timeout or restart never reports back
                $LastActivity = $Progress.LastUpdate ?? $Run.StartedAt ?? $Run.RequestedAt
                $LastActivity = if ($LastActivity -is [System.DateTimeOffset]) { $LastActivity.UtcDateTime } elseif ($LastActivity) { ([datetime]$LastActivity).ToUniversalTime() } else { $null }
                if ($Status -ne 'Error' -and $LastActivity -and $LastActivity -lt [datetime]::UtcNow.AddHours(-6)) {
                    $Status = 'Error'
                    $RunError = 'The run stopped before it finished (worker timeout or restart) and made no progress for 6 hours. Run it again.'
                    $null = Set-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ Status = 'Error'; ErrorMessage = $RunError }
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "NHI run $CaseId stopped without finishing; marked as failed" -Sev 'Warning'
                }
                if ($Status -ne 'Error') { Add-CIPPRealtimeWatch -JobId $Run.CaseId }
                $Summary = @{
                    CaseId             = $Run.CaseId
                    Status             = $Status
                    ServicePrincipalId = $Run.ServicePrincipalId
                    DisplayName        = $Run.DisplayName
                    RequestedAt        = $Run.RequestedAt
                    RequestedBy        = $Run.RequestedBy
                    StartedAt          = $Run.StartedAt
                    Progress           = $Progress
                    Waiting            = $Status -ne 'Error'
                }
                if ($Status -eq 'Error') { $Summary.Error = ($RunError ?? 'The NHI run failed') }
                $Summary
            } else {
                $Results = $Run.Results
                # the other tenants the app is in, limited to those this user may see
                if ($Results.OtherTenants) { $Results.OtherTenants = @($Results.OtherTenants | Select-CippAllowedTenantData -TenantProperty 'Tenant') }
                $Results | Add-Member -NotePropertyName 'Run' -NotePropertyValue ([pscustomobject]@{
                        CaseId      = $Run.CaseId
                        Status      = $Run.Status
                        ExtractedAt = $Run.ExtractedAt
                        RequestedAt = $Run.RequestedAt
                        RequestedBy = $Run.RequestedBy
                        Containment = @($Run.Containment | Where-Object { $_ })
                    }) -Force
                $Results
            }
        } elseif ($Start) {
            $RequestedBy = try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' }
            # the technician's own address (first x-forwarded-for hop) is never the attacker's
            $RequestedFromIP = ConvertTo-CIPPBecHostAddress -Address ([string](([string]$Headers.'x-forwarded-for' -split ',')[0])).Trim()
            $Cases = foreach ($Id in $ServicePrincipalIds) {
                try {
                    $Prepared = New-CIPPNhiRunRequest -TenantFilter $TenantFilter -ServicePrincipalId $Id -RequestedBy ([string]$RequestedBy) -RequestedFromIP ([string]$RequestedFromIP)
                    $null = Start-CIPPOrchestrator -InputObject $Prepared.InputObject
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Queued an NHI compromise investigation for $($Prepared.Name) [case $($Prepared.CaseId)]" -Sev 'Info'
                    [pscustomobject]@{ ServicePrincipalId = $Id; DisplayName = $Prepared.Name; CaseId = $Prepared.CaseId; Status = 'Waiting' }
                } catch {
                    $StartError = Get-CippException -Exception $_
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not start an NHI investigation for $Id`: $($StartError.NormalizedError)" -Sev 'Error' -LogData $StartError
                    [pscustomobject]@{ ServicePrincipalId = $Id; CaseId = $null; Status = 'Error'; Error = $StartError.NormalizedError }
                }
            }
            $Cases = @($Cases)
            if ($ServicePrincipalIds.Count -eq 1 -and $Cases[0].Status -eq 'Error') { throw $Cases[0].Error }
            $Body = if ($ServicePrincipalIds.Count -eq 1) {
                @{ CaseId = $Cases[0].CaseId; Status = 'Waiting'; Results = "Started an NHI compromise investigation of $($Cases[0].DisplayName)" }
            } else {
                $StatusCode = Get-CippBulkStatusCode -Total $Cases.Count -Failed @($Cases | Where-Object Status -EQ 'Error').Count
                @{ Cases = $Cases; Results = "Started $(@($Cases | Where-Object CaseId).Count) of $($Cases.Count) NHI compromise investigations" }
            }
        } else {
            if (-not $ServicePrincipalId) { throw [System.ArgumentException]::new('caseId or servicePrincipalId is required') }
            # the latest run that is not a failure; never starts one
            $Latest = @(Get-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -ServicePrincipalId $ServicePrincipalId | Where-Object { $_.Status -in @('Completed', 'Waiting', 'Running') }) | Select-Object -First 1
            $Body = if ($Latest) { @{ CaseId = $Latest.CaseId; Status = $Latest.Status } } else { @{ CaseId = $null; Status = $null; NoRuns = $true } }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "NHI check request failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Waiting = $false; Error = $ErrorMessage.NormalizedError; Results = $ErrorMessage.NormalizedError }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
