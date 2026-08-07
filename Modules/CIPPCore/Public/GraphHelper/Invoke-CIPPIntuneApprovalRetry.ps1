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

        This function is the second half of that handshake. It polls the approval request and, once
        approved, resubmits the write. While the request is still open it reschedules itself as a
        hidden one-off task, so a deferred change eventually completes without anyone in CIPP having
        to come back to it. It stops on any terminal state and after MaxAttempts checks.
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
    .PARAMETER Attempt
        Current check number. Managed by the reschedule - callers should leave it at the default.
    .PARAMETER MaxAttempts
        Number of hourly checks before giving up. Defaults to 72 - Intune expires a request that has
        not been processed within 3 days, so there is nothing left to complete after that.
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

        [int]$Attempt = 1,

        [int]$MaxAttempts = 72
    )

    $Uri = 'https://graph.microsoft.com/beta/{0}' -f $ResourcePath.TrimStart('/')

    try {
        # operationApprovalRequest has no requestId property - the approval code is the entity id.
        # The collection is read rather than the single entity so a code that turns out to be a
        # different identifier still resolves, and so a 404 on one id cannot mask a real failure.
        $ApprovalRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/operationApprovalRequests' -tenantid $TenantFilter |
            Where-Object { $_.id -eq $ApprovalCode -or $_.requestId -eq $ApprovalCode } | Select-Object -First 1
    } catch {
        # A lookup failure is transient as far as we know - fall through to the reschedule so a
        # blip does not strand an approved change.
        Write-Warning "Could not read approval request $ApprovalCode for $TenantFilter : $($_.Exception.Message)"
        $ApprovalRequest = $null
    }

    $Status = $ApprovalRequest.status

    if ($Status -eq 'completed') {
        $Message = "Approval request $ApprovalCode is already completed. $Type $ResourcePath needs no further action."
        Write-LogMessage -API 'IntuneApproval' -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    }

    if ($Status -eq 'approved') {
        try {
            $null = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -type $Type -AddedHeaders @{ 'x-msft-approval-code' = $ApprovalCode }
            $Message = "Approval request $ApprovalCode was approved. $Type $ResourcePath completed."
            Write-LogMessage -API 'IntuneApproval' -tenant $TenantFilter -message $Message -Sev 'Info'
            return $Message
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Approval request $ApprovalCode was approved but $Type $ResourcePath still failed: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -API 'IntuneApproval' -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
            return $Message
        }
    }

    # The API enum spells it 'cancelled'; the Intune console says 'Canceled'. Accept both.
    if ($Status -in @('rejected', 'cancelled', 'canceled', 'expired')) {
        $Message = "Approval request $ApprovalCode ended in state '$Status'. $Type $ResourcePath will not be performed."
        Write-LogMessage -API 'IntuneApproval' -tenant $TenantFilter -message $Message -Sev 'Warning'
        return $Message
    }

    # Still open (needsApproval), or the request could not be read this time round
    if ($Attempt -ge $MaxAttempts) {
        $Message = "Approval request $ApprovalCode was not approved within the 3 days Intune allows before a request expires. Giving up on $Type $ResourcePath - repeat the action in CIPP to raise a fresh request."
        Write-LogMessage -API 'IntuneApproval' -tenant $TenantFilter -message $Message -Sev 'Warning'
        return $Message
    }

    $TaskBody = @{
        TenantFilter  = $TenantFilter
        Name          = "Intune approval retry: $Type $ResourcePath"
        Command       = @{ value = 'Invoke-CIPPIntuneApprovalRetry' }
        Parameters    = [pscustomobject]@{
            TenantFilter = $TenantFilter
            ApprovalCode = $ApprovalCode
            ResourcePath = $ResourcePath
            Type         = $Type
            Attempt      = $Attempt + 1
            MaxAttempts  = $MaxAttempts
        }
        ScheduledTime = [int64](([datetime]::UtcNow.AddHours(1)) - (Get-Date '1/1/1970')).TotalSeconds
        Recurrence    = '0'
        PostExecution = @{}
        Reference     = "IntuneApproval-$ApprovalCode"
    }
    $null = Add-CIPPScheduledTask -Task $TaskBody -Hidden $true

    $Message = "Approval request $ApprovalCode is still awaiting approval (check $Attempt of $MaxAttempts). $Type $ResourcePath will be retried in an hour."
    Write-Information $Message
    return $Message
}
