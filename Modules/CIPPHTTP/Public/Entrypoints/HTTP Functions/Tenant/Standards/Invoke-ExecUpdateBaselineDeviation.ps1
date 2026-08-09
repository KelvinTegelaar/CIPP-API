function Invoke-ExecUpdateBaselineDeviation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Triage for baseline drift on a resolved (tenant, standard) row:
        Accept (reason required, optional expiry, optional remediate-on-expire),
        Deny (method remediate|delete - the engine remediates on the next run regardless of
        the configured posture, or holds Delete Pending for object-type standards),
        Clear (re-surface as Drift), AcceptPath (tolerate one property while others keep
        alerting), and CompleteTask (mark a manual task done). One Status column; timestamps
        are unix seconds.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Action = $Request.Body.action
        $TenantFilter = $Request.Body.tenantFilter
        $Standard = $Request.Body.standard
        if (-not ($Action -and $TenantFilter -and $Standard)) {
            throw 'Provide action, tenantFilter, and standard.'
        }
        if ($Action -in @('Accept', 'AcceptPath', 'DenyPath') -and -not $Request.Body.reason) {
            throw 'A reason is required to triage a deviation.'
        }

        $Table = Get-CippTable -tablename 'BaselineAlignment'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $SafeStandard = ConvertTo-CIPPODataFilterValue -Value $Standard
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

        # Standard-view bulk complete: mark this manual task done on EVERY tenant's row.
        if ($Action -eq 'CompleteTask' -and $TenantFilter -in @('AllTenants', 'allTenants')) {
            $Entities = @(Get-CIPPAzDataTableEntity @Table -Filter "StandardName eq '$SafeStandard'")
            if ($Entities.Count -eq 0) { throw "No resolved data for $Standard yet - run the baseline first." }
            $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
            $Table.Force = $true
            foreach ($TaskEntity in $Entities) {
                $TaskEntity | Add-Member -NotePropertyName 'Status' -NotePropertyValue 'Compliant' -Force
                $TaskEntity | Add-Member -NotePropertyName 'Compliant' -NotePropertyValue $true -Force
                $TaskEntity | Add-Member -NotePropertyName 'LastRemediated' -NotePropertyValue $Now -Force
                if ($TaskEntity.CurrentValue) {
                    $CurrentTask = $TaskEntity.CurrentValue | ConvertFrom-Json
                    $CurrentTask | Add-Member -NotePropertyName 'completed' -NotePropertyValue $true -Force
                    $TaskEntity | Add-Member -NotePropertyName 'CurrentValue' -NotePropertyValue (ConvertTo-Json -Compress -Depth 20 -InputObject $CurrentTask) -Force
                }
                Add-CIPPAzDataTableEntity @Table -Entity $TaskEntity
                $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TaskEntity.PartitionKey -Standard $Standard -Mode 'triage' -TriggeredBy $User -Outcome 'Task Completed' -Detail 'Marked completed for all tenants from the standard view'
            }
            $Message = "Marked the manual task $Standard as completed for $($Entities.Count) tenant$($Entities.Count -eq 1 ? '' : 's')."
            Write-LogMessage -headers $Request.Headers -API $APIName -message $Message -Sev 'Info'
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = [pscustomobject]@{ Results = $Message }
                })
        }

        $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and StandardName eq '$SafeStandard'"
        if (-not $Entity) {
            $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeStandard'"
        }
        if (-not $Entity) {
            throw "No resolved data for $Standard on $TenantFilter yet - run the baseline first."
        }
        $Entity = $Entity | Select-Object -First 1

        $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
        $Set = { param($Name, $Value) $Entity | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }

        switch ($Action) {
            'Accept' {
                & $Set 'Status' 'Accepted'
                & $Set 'DeviationReason' "$($Request.Body.reason)"
                & $Set 'DeviationBy' "$User"
                & $Set 'DeviationAt' $Now
                & $Set 'DeviationExpires' ($Request.Body.expires ?? '')
                & $Set 'RemediateOnExpire' ([bool]$Request.Body.remediateOnExpire)
                $Message = "Accepted the deviation on $Standard for $TenantFilter."
                $EventOutcome = 'Accepted'
                $EventDetail = 'Accepted the deviation{0}{1}' -f $(if ($Request.Body.reason) { ": $($Request.Body.reason)" }), $(if ($Request.Body.expires) { " (expires $($Request.Body.expires))" })
            }
            'Deny' {
                $Method = $Request.Body.method ?? 'remediate'
                if ($Method -notin @('remediate', 'delete')) {
                    throw "Unknown deny method '$Method'. Use remediate or delete."
                }
                & $Set 'Status' $(if ($Method -eq 'delete') { 'Denied - Delete Pending' } else { 'Denied - Remediate Pending' })
                & $Set 'DeviationReason' "$($Request.Body.reason)"
                & $Set 'DeviationBy' "$User"
                & $Set 'DeviationAt' $Now
                & $Set 'DeviationExpires' ''
                & $Set 'RemediateOnExpire' $false
                # A deny is an order to enforce the baseline; accepted property paths would
                # block the (whole-object) remediation, so the deny supersedes them.
                & $Set 'AcceptedPaths' '{}'
                $Message = "Denied the deviation on $Standard for $TenantFilter - $Method pending on the next run."
                $EventOutcome = $(if ($Method -eq 'delete') { 'Denied - Delete Ordered' } else { 'Denied - Remediation Ordered' })
                $EventDetail = 'Denied the deviation{0} - {1} on the next run' -f $(if ($Request.Body.reason) { ": $($Request.Body.reason)" }), $(if ($Method -eq 'delete') { 'the object is deleted' } else { 'the baseline is enforced' })
            }
            'Clear' {
                # Only a triaged status re-surfaces as Drift; clearing leftover accepted
                # paths from a Compliant row must not flag drift that is not there.
                if ("$($Entity.Status)" -in @('Accepted', 'Partially Accepted', 'Denied - Remediate Pending', 'Denied - Delete Pending')) {
                    & $Set 'Status' 'Drift'
                }
                & $Set 'DeviationReason' ''
                & $Set 'DeviationBy' ''
                & $Set 'DeviationAt' ''
                & $Set 'DeviationExpires' ''
                & $Set 'RemediateOnExpire' $false
                # Accepted property paths now drive the status too - a Clear that left them
                # behind would flip straight back to (Partially) Accepted on the next run.
                & $Set 'AcceptedPaths' '{}'
                $Message = "Cleared the triage and any accepted properties on $Standard for $TenantFilter - it re-surfaces as Drift."
                $EventOutcome = 'Triage Cleared'
                $EventDetail = 'Cleared the triage and any accepted properties - the deviation re-surfaces as Drift'
            }
            { $_ -in @('AcceptPath', 'DenyPath', 'ClearPath') } {
                $Path = $Request.Body.path
                if (-not $Path) { throw "$Action requires the property path." }
                $AcceptedPaths = if ($Entity.AcceptedPaths) { $Entity.AcceptedPaths | ConvertFrom-Json } else { [PSCustomObject]@{} }
                # Per-path verdicts: 'accept' tolerates that property's drift; 'denyDelete'
                # queues the path's object for deletion once delete executors exist. Both
                # count as triaged. ClearPath removes a single verdict.
                if ($Action -eq 'ClearPath') {
                    $AcceptedPaths.PSObject.Properties.Remove($Path)
                    $Message = "Cleared the triage on property $Path of $Standard for $TenantFilter - it re-surfaces as drift on the next run."
                    $EventOutcome = 'Property Triage Cleared'
                    $EventDetail = "Cleared the triage on '$Path' - it re-surfaces as drift on the next run"
                } else {
                    $Verdict = if ($Action -eq 'DenyPath') { 'denyDelete' } else { 'accept' }
                    $AcceptedPaths | Add-Member -NotePropertyName $Path -NotePropertyValue ([PSCustomObject]@{
                            reason  = $Request.Body.reason
                            by      = $User
                            at      = $Now
                            verdict = $Verdict
                        }) -Force
                    $Message = if ($Action -eq 'DenyPath') {
                        "Denied $Path of $Standard for $TenantFilter - it is deleted on the next remediation run. Other properties keep alerting."
                    } else {
                        "Accepted the deviation on property $Path of $Standard for $TenantFilter. Other properties keep alerting."
                    }
                    $EventOutcome = $(if ($Action -eq 'DenyPath') { 'Property Denied' } else { 'Property Accepted' })
                    $EventDetail = '{0} ''{1}''{2}' -f $(if ($Action -eq 'DenyPath') { 'Denied - queued for deletion:' } else { 'Accepted the deviation on' }), $Path, $(if ($Request.Body.reason) { " - $($Request.Body.reason)" })
                }
                & $Set 'AcceptedPaths' (ConvertTo-Json -Compress -Depth 20 -InputObject $AcceptedPaths)
                # Reflect the verdict in the status immediately instead of waiting for the
                # next run: rediff the stored values with all triaged paths filtered out.
                # Nothing left: all accepts -> Accepted; any deny-delete -> Delete Pending.
                # Anything left keeps alerting (Partially Accepted, or Drift when no
                # verdicts remain). Rows without stored values wait for the engine.
                if ($Entity.Status -in @('Drift', 'Partially Accepted', 'Accepted', 'Denied - Delete Pending') -and $Entity.ExpectedValue -and $Entity.CurrentValue) {
                    $AcceptedKeys = @($AcceptedPaths.PSObject.Properties.Name)
                    $DenyDeleteKeys = @($AcceptedPaths.PSObject.Properties | Where-Object { $_.Value.verdict -eq 'denyDelete' } | ForEach-Object { $_.Name })
                    $Remaining = $null
                    try {
                        $Differences = @(Compare-CIPPIntuneObject -ReferenceObject ($Entity.ExpectedValue | ConvertFrom-Json) -DifferenceObject ($Entity.CurrentValue | ConvertFrom-Json) | Where-Object { $_ })
                        $Remaining = @($Differences | Where-Object {
                                $Property = $_.Property
                                -not ($AcceptedKeys | Where-Object { $Property -eq $_ -or $Property.StartsWith("$_.") })
                            })
                    } catch { $Remaining = $null }
                    if ($null -ne $Remaining) {
                        $NewStatus = if ($Remaining.Count -gt 0) {
                            $(if ($AcceptedKeys.Count -gt 0) { 'Partially Accepted' } else { 'Drift' })
                        } elseif ($DenyDeleteKeys.Count -gt 0) { 'Denied - Delete Pending' }
                        elseif ($AcceptedKeys.Count -gt 0) { 'Accepted' }
                        else { 'Drift' }
                        & $Set 'Status' $NewStatus
                        if ($Action -ne 'ClearPath') {
                            & $Set 'DeviationReason' "$($Request.Body.reason)"
                            & $Set 'DeviationBy' "$User"
                            & $Set 'DeviationAt' $Now
                        }
                        if ($Remaining.Count -gt 0) {
                            $Message = "$Message $($Remaining.Count) untriaged deviating $(if ($Remaining.Count -eq 1) { 'property keeps' } else { 'properties keep' }) alerting."
                        }
                    }
                }
            }
            'CompleteTask' {
                & $Set 'Status' 'Compliant'
                & $Set 'Compliant' $true
                & $Set 'LastRemediated' $Now
                if ($Entity.CurrentValue) {
                    $Current = $Entity.CurrentValue | ConvertFrom-Json
                    $Current | Add-Member -NotePropertyName 'completed' -NotePropertyValue $true -Force
                    & $Set 'CurrentValue' (ConvertTo-Json -Compress -Depth 20 -InputObject $Current)
                }
                $Message = "Marked the manual task $Standard as completed for $TenantFilter."
                $EventOutcome = 'Task Completed'
                $EventDetail = 'Marked the manual task as completed'
            }
            default {
                throw "Unknown action '$Action'. Use Accept, Deny, Clear, AcceptPath, DenyPath, ClearPath, or CompleteTask."
            }
        }

        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity $Entity
        $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TenantFilter -Standard $Standard -Mode 'triage' -TriggeredBy $User -Outcome $EventOutcome -Detail $EventDetail

        Write-LogMessage -headers $Request.Headers -API $APIName -message $Message -Sev 'Info'
        $Results = [pscustomobject]@{ Results = $Message }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to update deviation: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to update deviation: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
