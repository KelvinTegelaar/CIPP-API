function Invoke-ExecJITAdminRequestDecision {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .SYNOPSIS
        Approve or reject a pending JIT Admin request
    .DESCRIPTION
        Records an approval or rejection on a pending JIT Admin request. The approver must hold one of the configured approver roles and cannot approve their own request. Any rejection ends the request; once the required number of approvals is reached the request is provisioned.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $RequestId = $Request.Body.RequestId
    $Decision = switch ($Request.Body.Decision) {
        'Approve' { 'Approve' }
        'Reject' { 'Reject' }
    }
    # Required when rejecting; sent to the requester
    $Note = $Request.Body.Note

    $Table = Get-CIPPTable -TableName 'JITAdminRequests'
    try {
        if (-not $Decision) { $FailCode = [HttpStatusCode]::BadRequest; throw 'Decision must be Approve or Reject.' }
        if ($Decision -eq 'Reject' -and [string]::IsNullOrWhiteSpace($Note)) { $FailCode = [HttpStatusCode]::BadRequest; throw 'A note is required when rejecting a request.' }
        $ParsedId = [guid]::Empty
        if (-not [guid]::TryParse([string]$RequestId, [ref]$ParsedId)) { $FailCode = [HttpStatusCode]::BadRequest; throw 'Invalid request id.' }
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'JITAdminRequest' and RowKey eq '$ParsedId'"
        if (-not $Row -or $Row.Tenant -ne $TenantFilter) { $FailCode = [HttpStatusCode]::NotFound; throw 'JIT Admin request not found.' }
        if ($Row.State -ne 'Pending') { $FailCode = [HttpStatusCode]::BadRequest; throw "This request is already $($Row.State.ToLower())." }

        $CallingUser = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        if ($Decision -eq 'Approve' -and $CallingUser -eq $Row.RequestedBy) { $FailCode = [HttpStatusCode]::Forbidden; throw 'You cannot approve your own request.' }
        $ApproverRoles = @($Row.ApproverRoles | ConvertFrom-Json)
        if (@(Get-CIPPAccessRole -Headers $Headers).Where({ $_ -in $ApproverRoles }).Count -eq 0) {
            $FailCode = [HttpStatusCode]::Forbidden
            throw "Only users with one of these roles can decide on this request: $($ApproverRoles -join ', ')"
        }

        $Decisions = [System.Collections.Generic.List[object]]::new()
        foreach ($Existing in @($Row.Decisions | ConvertFrom-Json)) { $Decisions.Add($Existing) }
        if ($Decisions.By -contains $CallingUser) { $FailCode = [HttpStatusCode]::BadRequest; throw 'You have already approved this request.' }
        $Decisions.Add([pscustomobject]@{ By = $CallingUser; At = (Get-Date).ToUniversalTime().ToString('o'); Decision = $Decision; Note = [string]$Note })
        $Approvals = @($Decisions.Where({ $_.Decision -eq 'Approve' })).Count
        $NewState = if ($Decision -eq 'Reject') { 'Rejected' } elseif ($Approvals -ge [int]$Row.RequiredApprovals) { 'Approved' } else { 'Pending' }
        if ($NewState -eq 'Approved' -and [int64]$Row.EndDate -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
            $FailCode = [HttpStatusCode]::BadRequest
            throw 'The requested access window has already ended. Reject this request instead.'
        }

        try {
            $null = Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $Row.PartitionKey
                RowKey       = $Row.RowKey
                State        = $NewState
                Decisions    = [string](ConvertTo-Json -InputObject @($Decisions) -Compress)
                ETag         = $Row.ETag
            }
        } catch {
            throw 'This request was updated by someone else. Refresh and try again.'
        }
        $Verb = $Decision -eq 'Approve' ? 'approved' : 'rejected'
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$CallingUser $Verb the JIT Admin request for $($Row.TargetUser) ($($Row.RoleNames))$(if ($Note) { ": $Note" })" -Sev 'Info'

        $Results = switch ($NewState) {
            'Rejected' {
                Send-CIPPJITAdminApprovalNotification -ApprovalRequest $Row -Status 'Rejected' -Note $Note
                "Rejected the JIT Admin request for $($Row.TargetUser)."
            }
            'Pending' {
                "Approval recorded ($Approvals of $($Row.RequiredApprovals))."
            }
            'Approved' {
                $Provision = Invoke-ExecJITAdmin -TriggerMetadata $null -Request ([pscustomobject]@{
                        Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecJITAdmin' }
                        Headers = ($Row.RequesterHeaders | ConvertFrom-Json -AsHashtable)
                        Body    = [pscustomobject]@{ ApprovalRequestId = $Row.RowKey }
                    })
                $ProvisionResults = @($Provision.Body.Results | ForEach-Object { $_.resultText ?? $_ })
                $Update = @{ PartitionKey = $Row.PartitionKey; RowKey = $Row.RowKey; Results = [string]($ProvisionResults -join "`n") }
                if ($Provision.StatusCode -ne [HttpStatusCode]::OK) { $Update.State = 'Failed' }
                $null = Update-AzDataTableEntity @Table -Entity $Update
                Send-CIPPJITAdminApprovalNotification -ApprovalRequest $Row -Status 'Approved' -Note $Note -Results $ProvisionResults
                "Approved the JIT Admin request for $($Row.TargetUser)."
                $ProvisionResults
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = $FailCode ?? [HttpStatusCode]::InternalServerError
        $Results = $_.Exception.Message
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = @($Results) }
        })
}
