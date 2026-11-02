function Invoke-ListIntuneApprovalRequests {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .SYNOPSIS
        List Intune multi-admin approval requests
    .DESCRIPTION
        Lists the multi-admin approval (MAA) requests raised in a tenant. When an access policy protects
        a resource type, Intune defers the change and records it here until a second administrator
        approves it, so this is where a change made from CIPP that appears to have done nothing ends up.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter
    # Only return requests still waiting on a decision. Off by default so the table shows history too.
    $PendingOnly = $Request.Query.PendingOnly -eq $true

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required' }
            })
    }

    try {
        $Uri = 'https://graph.microsoft.com/beta/deviceManagement/operationApprovalRequests'
        if ($PendingOnly) {
            $Uri = "$($Uri)?`$filter=status eq 'needsApproval'"
        }
        $ApprovalRequests = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter

        $Results = foreach ($ApprovalRequest in $ApprovalRequests) {
            # payloadOperation, payloadName and payload are absent from the published schema but are
            # returned by the service, and they are the only description of what is actually held -
            # without them a row says a change is pending but not which one.
            #
            # requestor/approver are identitySets that the service leaves null in practice, including
            # for requests raised through Graph. They are projected anyway rather than dropped, so
            # they populate on their own if Microsoft starts filling them in.
            [PSCustomObject]@{
                id                    = $ApprovalRequest.id
                status                = $ApprovalRequest.status
                operation             = $ApprovalRequest.payloadOperation
                target                = $ApprovalRequest.payloadName
                operationTypes        = @($ApprovalRequest.requiredOperationApprovalPolicyTypes) -join ', '
                requestJustification  = $ApprovalRequest.requestJustification
                approvalJustification = $ApprovalRequest.approvalJustification
                requestedBy           = $ApprovalRequest.requestor.user.displayName ?? $ApprovalRequest.requestor.application.displayName
                approvedBy            = $ApprovalRequest.approver.user.displayName ?? $ApprovalRequest.approver.application.displayName
                requestDateTime       = $ApprovalRequest.requestDateTime
                expirationDateTime    = $ApprovalRequest.expirationDateTime
                lastModifiedDateTime  = $ApprovalRequest.lastModifiedDateTime
                payload               = $ApprovalRequest.payload
            }
        }
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to list Intune approval requests: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results = $ErrorMessage.NormalizedError
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
