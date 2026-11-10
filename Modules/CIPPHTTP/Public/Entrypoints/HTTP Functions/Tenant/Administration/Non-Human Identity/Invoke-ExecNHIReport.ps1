function Invoke-ExecNHIReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .SYNOPSIS
        Manages a stored non-human identity (NHI) compromise investigation.
    .DESCRIPTION
        Action=Delete removes an NHI run permanently: its results payload and the run row. Runs are otherwise kept indefinitely.
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
        if (-not $TenantFilter -or -not $CaseId) { throw [System.ArgumentException]::new('tenantFilter and caseId are required') }
        if ($Action -ne 'Delete') { throw [System.ArgumentException]::new("Unknown action '$Action'") }
        $Result = Remove-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted NHI run $CaseId" -Sev 'Info'
        $Body = @{ Results = $Result }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "NHI run action '$Action' failed for $CaseId`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
