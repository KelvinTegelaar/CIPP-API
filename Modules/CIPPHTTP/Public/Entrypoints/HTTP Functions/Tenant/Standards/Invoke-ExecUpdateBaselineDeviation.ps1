function Invoke-ExecUpdateBaselineDeviation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Triage for Baseline deviations on a resolved (tenant, standard) row:
        Accept (reason, optional expiry, optional remediate-on-expire), Suppress (mute alerts,
        stays non-compliant), Clear (re-surface as Detected), AcceptPath (tolerate one property
        while others keep alerting), and CompleteTask (mark a manual task done). Writes the
        BaselineAlignment columns from design doc §4.2 directly.
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
                & $Set 'DeviationState' 'Accepted'
                & $Set 'DeviationReason' "$($Request.Body.reason)"
                & $Set 'DeviationBy' "$User"
                & $Set 'DeviationAt' $Now
                & $Set 'DeviationExpires' ($Request.Body.expires ?? '')
                & $Set 'RemediateOnExpire' ([bool]$Request.Body.remediateOnExpire)
                $Message = "Accepted the deviation on $Standard for $TenantFilter."
            }
            'Suppress' {
                & $Set 'DeviationState' 'Suppressed'
                & $Set 'DeviationReason' "$($Request.Body.reason)"
                & $Set 'DeviationBy' "$User"
                & $Set 'DeviationAt' $Now
                & $Set 'DeviationExpires' ($Request.Body.expires ?? '')
                $Message = "Suppressed alerts for $Standard on $TenantFilter."
            }
            'Clear' {
                & $Set 'DeviationState' 'Detected'
                & $Set 'DeviationReason' ''
                & $Set 'DeviationBy' ''
                & $Set 'DeviationAt' ''
                & $Set 'DeviationExpires' ''
                & $Set 'RemediateOnExpire' $false
                $Message = "Cleared the deviation status on $Standard for $TenantFilter - it re-surfaces as Detected."
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
                $Message = "Accepted the deviation on property $Path of $Standard for $TenantFilter. Other properties keep alerting."
            }
            'CompleteTask' {
                & $Set 'DeviationState' 'Compliant'
                & $Set 'Compliant' $true
                & $Set 'LastOutcome' 'Remediated'
                & $Set 'LastRemediated' $Now
                if ($Entity.CurrentValue) {
                    $Current = $Entity.CurrentValue | ConvertFrom-Json
                    $Current | Add-Member -NotePropertyName 'completed' -NotePropertyValue $true -Force
                    & $Set 'CurrentValue' (ConvertTo-Json -Compress -Depth 20 -InputObject $Current)
                }
                $Message = "Marked the manual task $Standard as completed for $TenantFilter."
            }
            default {
                throw "Unknown action '$Action'. Use Accept, Suppress, Clear, AcceptPath, or CompleteTask."
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
