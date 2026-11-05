function New-CIPPIntuneApprovalRequest {
    <#
    .SYNOPSIS
        Raises an Intune multi-admin approval request for a write Intune refused, and schedules its completion.
    .DESCRIPTION
        On a tenant with multi-admin approval (MAA), Intune refuses a protected write that carries no
        x-msft-approval-justification header, and raises nothing. New-GraphPOSTRequest treats that refusal
        as the signal to call this function, which resends the same write with a justification so Intune
        raises an approval request, then hands the request to Invoke-CIPPIntuneApprovalRetry to complete
        once a second admin approves it.

        The request is always raised app-only. In a customer tenant the GDAP user is a foreign principal,
        so a request raised with the delegated token is stored with no requestor and can never be completed.

        Throws once the request is raised: the write has not happened yet, so callers must not treat it as
        done. The exception carries the request id in Data['IntuneApprovalCode'].
    .PARAMETER Uri
        Full beta Graph URL of the refused write.
    .PARAMETER Justification
        Plain text reason shown to the approver. Encoded to base64 here, as Intune requires.
    .PARAMETER AssignParams
        Optional Set-CIPPAssignedPolicy parameters to apply once the write completes. Assignment is its own
        approval request, so it can only be sent after the policy exists.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [string]$Type = 'POST',

        $Body,

        [string]$Justification,

        [hashtable]$AssignParams
    )

    if ($Uri -notmatch '^https://graph\.microsoft\.com/beta/(.+)$') {
        throw "This change requires Intune multi-admin approval, which CIPP can only request for Graph beta writes: $Uri"
    }
    $ResourcePath = $Matches[1]

    if ([string]::IsNullOrWhiteSpace($Justification)) { $Justification = "CIPP: $($Type.ToUpper()) $ResourcePath" }
    if ($Justification.Length -gt 1024) { $Justification = $Justification.Substring(0, 1024) }
    $EncodedJustification = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Justification))

    try {
        # Intune never performs a protected write inline, so this is expected to fail with the approval code.
        return New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -type $Type -body $Body -AsApp $true -AddedHeaders @{ 'x-msft-approval-justification' = $EncodedJustification }
    } catch {
        # The code arrives in the x-msft-approval-code response header, which Intune echoes into the error body.
        # Anything else, such as "An active Approval Request already exists", goes back to the caller as is.
        $RawError = '{0} {1}' -f $_.Exception.Data['RawErrorBody'], $_.Exception.Message
        if ($RawError -notmatch 'x-msft-approval-code["'':\\\s]*([0-9a-fA-F-]{36})') { throw }
        $ApprovalCode = $Matches[1]
    }

    $Message = "This change requires Intune multi-admin approval. Approval request $ApprovalCode has been raised - CIPP will complete it once another administrator approves it in Intune."
    try {
        # One hourly task per request. Invoke-CIPPIntuneApprovalRetry ends the recurrence itself
        # once the request is resolved.
        $Now = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        $null = Add-CIPPScheduledTask -Hidden $true -Task @{
            TenantFilter  = $TenantFilter
            Name          = "Intune approval: $($Type.ToUpper()) $ResourcePath"
            Command       = @{ value = 'Invoke-CIPPIntuneApprovalRetry' }
            Parameters    = [pscustomobject]@{
                TenantFilter = $TenantFilter
                ApprovalCode = $ApprovalCode
                ResourcePath = $ResourcePath
                Type         = $Type.ToUpper()
                Body         = $Body
                AssignParams = $AssignParams
                RaisedAt     = $Now
            }
            ScheduledTime = $Now + 3600
            Recurrence    = '1h'
            PostExecution = @{}
            Reference     = "IntuneApproval-$ApprovalCode"
        }
    } catch {
        $Message = "This change requires Intune multi-admin approval. Approval request $ApprovalCode has been raised, but CIPP could not schedule its completion ($($_.Exception.Message)). Reject it in Intune and repeat the action."
    }
    Write-LogMessage -API 'IntuneApproval' -tenant $TenantFilter -message "$($Type.ToUpper()) $ResourcePath : $Message" -Sev 'Warning'

    $ApprovalException = [System.Exception]::new($Message)
    $ApprovalException.Data['IntuneApprovalCode'] = $ApprovalCode
    throw $ApprovalException
}
