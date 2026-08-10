function Get-CIPPAlertIntuneApprovalRequests {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        # Multi-admin approval holds a change until a second admin approves it. Nothing tells the
        # requestor it is waiting, so a pending request is a change someone believes they already made.
        # Filtered server side - a decided request is never of interest here, and this runs per tenant.
        $Uri = "https://graph.microsoft.com/beta/deviceManagement/operationApprovalRequests?`$filter=status eq 'needsApproval'"
        $ApprovalRequests = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -ErrorAction Stop

        $AlertData = foreach ($ApprovalRequest in $ApprovalRequests) {
            # payloadOperation and payloadName are absent from the published schema but are returned
            # by the service. They are what makes the alert readable - the requestor identitySet is
            # left null even for requests raised through Graph, so there is no 'who' to report.
            $Operation = ($ApprovalRequest.payloadOperation ?? 'change').ToLower()
            $Target = $ApprovalRequest.payloadName ?? (@($ApprovalRequest.requiredOperationApprovalPolicyTypes) -join ', ')
            $Message = 'Intune {0} of "{1}" is waiting for multi-admin approval and expires {2}' -f $Operation, $Target, $ApprovalRequest.expirationDateTime

            $ApprovalRequest | Select-Object -Property id, status, requestDateTime, expirationDateTime, requestJustification,
            @{Name = 'operation'; Expression = { $ApprovalRequest.payloadOperation } },
            @{Name = 'target'; Expression = { $ApprovalRequest.payloadName } },
            @{Name = 'Message'; Expression = { $Message } }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Failed to check Intune multi-admin approval requests for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
