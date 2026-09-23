function Invoke-ExecBECBulkCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Queues Business Email Compromise investigations for many users at once.
    .DESCRIPTION
        Queues one BEC investigation per user as a single orchestration with a queue entry for progress. Accepts either an array of { UserIds, tenantFilter } items (the Users table bulk action) or one object with UserIds[]. Each run gets its own case id; results appear on the BEC Reports page and each user's Compromise Remediation tab.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Entries = @($Request.Body | Where-Object { $_ })
        if ($Entries.Count -eq 0) { throw 'No request body' }
        $Unwrap = { param($Value) if ($Value -and $Value.PSObject.Properties['value']) { $Value.value } else { $Value } }
        $TenantFilter = [string](& $Unwrap ($Entries | ForEach-Object { $_.tenantFilter } | Where-Object { $_ } | Select-Object -First 1))
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        # object ids of the users to investigate
        $UserIds = @($Entries | ForEach-Object { @($_.UserIds) } | Where-Object { $_ } | ForEach-Object { [string](& $Unwrap $_) } | Where-Object { $_ } | Select-Object -Unique)
        if ($UserIds.Count -eq 0) { throw 'No users to check' }

        # Resolve UPN and display name in chunks of 15 ids
        $Resolved = @{}
        $Requests = for ($i = 0; $i -lt $UserIds.Count; $i += 15) {
            $Chunk = $UserIds[$i..([Math]::Min($i + 14, $UserIds.Count - 1))]
            @{ id = "u$i"; method = 'GET'; url = "users?`$filter=id in ('$($Chunk -join "','")')&`$select=id,userPrincipalName,displayName" }
        }
        foreach ($Response in @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true)) {
            foreach ($User in @($Response.body.value)) { if ($User.id) { $Resolved[[string]$User.id] = $User } }
        }

        $RequestedBy = try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' }
        # the technician's own address (first x-forwarded-for hop) is never the user's or the attacker's
        $RequestedFromIP = ConvertTo-CIPPBecHostAddress -Address ([string](([string]$Headers.'x-forwarded-for' -split ',')[0])).Trim()
        $Queue = New-CippQueueEntry -Name "BEC investigation - $TenantFilter" -Link "/identity/reports/bec-reports?tenantFilter=$TenantFilter" -Reference "bec-$TenantFilter-$([guid]::NewGuid().ToString('N'))" -TotalTasks $UserIds.Count
        $Batch = [System.Collections.Generic.List[object]]::new()
        $Cases = [System.Collections.Generic.List[object]]::new()
        foreach ($UserId in $UserIds) {
            $User = $Resolved[$UserId]
            if (-not $User) {
                $Cases.Add([pscustomobject]@{ UserId = $UserId; UserPrincipalName = $null; CaseId = $null; Error = 'User not found' })
                continue
            }
            $Prepared = New-CIPPBecRunRequest -TenantFilter $TenantFilter -UserId ([string]$User.id) -UserPrincipalName ([string]$User.userPrincipalName) -DisplayName ([string]$User.displayName) -RequestedBy ([string]$RequestedBy) -QueueId ([string]$Queue.RowKey) -RequestedFromIP ([string]$RequestedFromIP)
            $Batch.Add($Prepared.Item)
            $Cases.Add([pscustomobject]@{ UserId = [string]$User.id; UserPrincipalName = [string]$User.userPrincipalName; CaseId = $Prepared.CaseId })
        }
        if ($Batch.Count -eq 0) { throw 'None of the selected users could be resolved' }
        $Unresolved = @($Cases | Where-Object { $_.Error } | ForEach-Object { $_.UserId })
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'BECRunOrchestrator'
            Batch            = @($Batch)
            SkipLog          = $true
        }
        $null = Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Queued $($Batch.Count) BEC investigation(s) (queue $($Queue.RowKey))" -Sev 'Info'
        $Body = @{
            Results = "Queued $($Batch.Count) BEC investigation(s). Results appear on the BEC Reports page and each user's Compromise Remediation tab.$(if ($Unresolved.Count -gt 0) { " $($Unresolved.Count) selected user(s) could not be found and were skipped: $($Unresolved -join ', ')." })"
            QueueId = $Queue.RowKey
            Cases   = @($Cases)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Bulk BEC investigation not queued: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Bulk BEC investigation not queued: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
