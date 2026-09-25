function Invoke-ExecBECReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .SYNOPSIS
        Manages a stored Business Email Compromise run.
    .DESCRIPTION
        Action=Delete removes a BEC run permanently: its results payload, its evidence package and the run row. Runs are otherwise kept indefinitely.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Currently only Delete
    $Action = [string]$Request.Body.Action
    $CaseId = [string]$Request.Body.caseId

    try {
        if (-not $CaseId) { throw 'caseId is required' }
        if ($Action -ne 'Delete') { throw "Unknown action '$Action'" }
        $Result = Remove-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted BEC run $CaseId" -Sev 'Info'
        $Body = @{ Results = $Result }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC run action '$Action' failed for $CaseId`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
