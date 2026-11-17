function Invoke-ListOneDriveCopyToUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.OneDrive.Read
    .SYNOPSIS
        Status of a OneDrive copy
    .DESCRIPTION
        Returns the state of a OneDrive copy started by ExecOneDriveCopyToUser: overall and per recipient (Queued, InProgress, Completed or Failed), with the number of files and bytes copied and any errors. Completed and Failed are final. SharePoint is checked at most once a minute per operation and for at most 100 unfinished copy jobs per call; within that minute the stored state is returned. Remove the leaver's licences only once State is Completed.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter
    # The OperationId returned by ExecOneDriveCopyToUser.
    $OperationId = $Request.Query.OperationId

    if (-not $Request.Query.tenantFilter) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if (-not $Request.Query.OperationId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'OperationId is required.' } })
    }

    try {
        $Result = Update-CIPPOneDriveCopyToUserStatus -TenantFilter $TenantFilter -OperationId $OperationId
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to retrieve the OneDrive copy status: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
