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
        if ($Action -in @('Accept', 'AcceptPath') -and -not $Request.Body.reason) {
            throw 'A reason is required to accept a deviation.'
        }

        $Table = Get-CippTable -tablename 'BaselineAlignment'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $SafeStandard = ConvertTo-CIPPODataFilterValue -Value $Standard

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

        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
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
            }
            'AcceptPath' {
                $Path = $Request.Body.path
                if (-not $Path) { throw 'AcceptPath requires the property path to accept.' }
                $AcceptedPaths = if ($Entity.AcceptedPaths) { $Entity.AcceptedPaths | ConvertFrom-Json } else { [PSCustomObject]@{} }
                $AcceptedPaths | Add-Member -NotePropertyName $Path -NotePropertyValue ([PSCustomObject]@{
                        reason = $Request.Body.reason
                        by     = $User
                        at     = $Now
                    }) -Force
                & $Set 'AcceptedPaths' (ConvertTo-Json -Compress -Depth 20 -InputObject $AcceptedPaths)
                # Reflect the acceptance in the status immediately instead of waiting for the
                # next run: rediff the stored values with the accepted paths filtered out -
                # nothing left means every deviating property is accepted (Accepted), anything
                # left keeps alerting (Partially Accepted). Denied rows keep the operator's
                # order; rows without stored values wait for the engine.
                $Message = "Accepted the deviation on property $Path of $Standard for $TenantFilter. Other properties keep alerting."
                if ($Entity.Status -in @('Drift', 'Partially Accepted', 'Accepted') -and $Entity.ExpectedValue -and $Entity.CurrentValue) {
                    $AcceptedKeys = @($AcceptedPaths.PSObject.Properties.Name)
                    $Remaining = $null
                    try {
                        $Differences = @(Compare-CIPPIntuneObject -ReferenceObject ($Entity.ExpectedValue | ConvertFrom-Json) -DifferenceObject ($Entity.CurrentValue | ConvertFrom-Json) | Where-Object { $_ })
                        $Remaining = @($Differences | Where-Object {
                                $Property = $_.Property
                                -not ($AcceptedKeys | Where-Object { $Property -eq $_ -or $Property.StartsWith("$_.") })
                            })
                    } catch { $Remaining = $null }
                    if ($null -ne $Remaining) {
                        & $Set 'Status' $(if ($Remaining.Count -eq 0) { 'Accepted' } else { 'Partially Accepted' })
                        & $Set 'DeviationReason' "$($Request.Body.reason)"
                        & $Set 'DeviationBy' "$User"
                        & $Set 'DeviationAt' $Now
                        $Message = if ($Remaining.Count -eq 0) {
                            "Accepted the deviation on property $Path of $Standard for $TenantFilter - every deviating property is now accepted."
                        } else {
                            "Accepted the deviation on property $Path of $Standard for $TenantFilter. $($Remaining.Count) unaccepted deviating $(if ($Remaining.Count -eq 1) { 'property keeps' } else { 'properties keep' }) alerting."
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
            }
            default {
                throw "Unknown action '$Action'. Use Accept, Deny, Clear, AcceptPath, or CompleteTask."
            }
        }

        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity $Entity

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
