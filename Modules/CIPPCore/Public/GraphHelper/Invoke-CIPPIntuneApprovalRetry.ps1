function Invoke-CIPPIntuneApprovalRetry {
    <#
    .SYNOPSIS
        Completes an Intune write that was deferred by multi-admin approval.
    .DESCRIPTION
        Intune multi-admin approval (MAA) never performs a protected write inline. The original
        request registers an approval request and fails, returning its id in the
        x-msft-approval-code response header. The change only happens when the request has been
        approved by a second, interactive admin and the caller resubmits the original request with
        the approval code in the x-msft-approval-code header.

        Intune binds a request to its requestor, so the resubmission is sent app-only, like the
        request New-CIPPIntuneApprovalRequest raised, and carries the original body - creates,
        updates and assignments cannot complete without it.

        This function is the second half of that handshake. New-CIPPIntuneApprovalRequest schedules
        it as one hourly recurring task per approval request. Each run reads the request's status
        and, once approved, resubmits the write. On any terminal state, and once Intune's 3-day
        window has passed, it ends its own recurrence so the task completes.
    .PARAMETER TenantFilter
        Tenant the approval request and the original write belong to.
    .PARAMETER ApprovalCode
        Approval request id from the x-msft-approval-code header of the original response.
    .PARAMETER ResourcePath
        Graph resource path of the original request, relative to the beta endpoint - for example
        'deviceManagement/configurationPolicies/<id>'. Only a path is accepted, never a full URL:
        this function runs from the scheduler, so it must not be usable to call arbitrary hosts.
    .PARAMETER Type
        HTTP method of the original request. Defaults to DELETE.
    .PARAMETER Body
        Body of the original request, resent unchanged with the approval code.
    .PARAMETER AssignParams
        Optional Set-CIPPAssignedPolicy parameters to apply once the write completes. PlatformType,
        Type and PolicyId are taken from ResourcePath and the created object when not given. The
        assignment is its own approval request on a protected policy, which Set-CIPPAssignedPolicy
        raises in turn.
    .PARAMETER RaisedAt
        Unix time the approval request was raised. Intune expires a request that has not been
        processed within 3 days, so the task stops checking after that. 0 means no deadline.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string]$ApprovalCode,

        [Parameter(Mandatory = $true)]
        [ValidatePattern("^[A-Za-z0-9/_.\-'()]+$")]
        [string]$ResourcePath,

        [ValidateSet('DELETE', 'POST', 'PATCH', 'PUT')]
        [string]$Type = 'DELETE',

        [string]$Body,

        [hashtable]$AssignParams,

        [int64]$RaisedAt = 0
    )

    $Uri = 'https://graph.microsoft.com/beta/{0}' -f $ResourcePath.TrimStart('/')

    # Ends the recurring task this runs in. The scheduler re-reads Recurrence after the run and marks
    # the task Completed instead of planning the next check. A no-op outside the scheduler.
    $StopChecking = {
        param($Message, $Sev)
        Write-LogMessage -API 'IntuneApproval' -tenant $TenantFilter -message $Message -Sev $Sev
        $TaskId = $script:CippScheduledTaskIdStorage.Value
        if ($TaskId) {
            $Table = Get-CippTable -tablename 'ScheduledTasks'
            $null = Update-AzDataTableEntity -Force @Table -Entity @{ PartitionKey = 'ScheduledTask'; RowKey = [string]$TaskId; Recurrence = '0' }
        }
        $Message
    }

    try {
        # operationApprovalRequest has no requestId property - the approval code is the entity id.
        # The collection is read rather than the single entity so a code that turns out to be a
        # different identifier still resolves, and so a 404 on one id cannot mask a real failure.
        $ApprovalRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/operationApprovalRequests' -tenantid $TenantFilter |
            Where-Object { $_.id -eq $ApprovalCode -or $_.requestId -eq $ApprovalCode } | Select-Object -First 1
    } catch {
        # A lookup failure is transient as far as we know - fall through to the next check so a
        # blip does not strand an approved change.
        Write-Warning "Could not read approval request $ApprovalCode for $TenantFilter : $($_.Exception.Message)"
        $ApprovalRequest = $null
    }

    $Status = $ApprovalRequest.status

    if ($Status -eq 'completed') {
        return & $StopChecking "Approval request $ApprovalCode is already completed. $Type $ResourcePath needs no further action." 'Info'
    }

    if ($Status -eq 'approved') {
        try {
            $Result = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -type $Type -body $Body -AsApp $true -AddedHeaders @{ 'x-msft-approval-code' = $ApprovalCode }
            $Message = "Approval request $ApprovalCode was approved. $Type $ResourcePath completed."
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            return & $StopChecking "Approval request $ApprovalCode was approved but $Type $ResourcePath still failed: $($ErrorMessage.NormalizedError)" 'Error'
        }
        if ($AssignParams) {
            # 'deviceManagement/configurationPolicies/<id>' or "deviceManagement/deviceConfigurations('<id>')"
            $Segments = $ResourcePath -split '/'
            $AssignParams.TenantFilter = $TenantFilter
            if (-not $AssignParams.PlatformType) { $AssignParams.PlatformType = $Segments[0] }
            if (-not $AssignParams.Type) { $AssignParams.Type = $Segments[1] -replace '\(.*$', '' }
            if (-not $AssignParams.PolicyId) {
                $AssignParams.PolicyId = $Result.id ?? $(if ($Segments[1] -match "\('?([^')]+)'?\)") { $Matches[1] } else { $Segments[2] })
            }
            try {
                $null = Set-CIPPAssignedPolicy @AssignParams
                $Message = "$Message Assignment applied."
            } catch {
                # On a protected policy this is the assignment's own approval request being raised.
                $Message = "$Message Assignment not applied yet: $($_.Exception.Message)"
            }
        }
        return & $StopChecking $Message 'Info'
    }

    # The API enum spells it 'cancelled'; the Intune console says 'Canceled'. Accept both.
    if ($Status -in @('rejected', 'cancelled', 'canceled', 'expired')) {
        return & $StopChecking "Approval request $ApprovalCode ended in state '$Status'. $Type $ResourcePath will not be performed." 'Warning'
    }

    # Still open (needsApproval), or the request could not be read this time round
    $Now = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
    if ($RaisedAt -gt 0 -and $Now -gt $RaisedAt + 3 * 86400 + 3600) {
        return & $StopChecking "Approval request $ApprovalCode was not approved within the 3 days Intune allows before a request expires. Giving up on $Type $ResourcePath - repeat the action in CIPP to raise a fresh request." 'Warning'
    }

    # Logged as well as returned: each run overwrites the task's result, the log keeps every check.
    $Message = "Approval request $ApprovalCode is still awaiting approval ($(if ($Status) { $Status } else { 'status unavailable' })). $Type $ResourcePath will be checked again in an hour."
    Write-LogMessage -API 'IntuneApproval' -tenant $TenantFilter -message $Message -Sev 'Info'
    return $Message
}
