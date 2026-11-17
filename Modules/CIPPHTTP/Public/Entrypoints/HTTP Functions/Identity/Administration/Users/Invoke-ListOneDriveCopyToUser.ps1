function Invoke-ListOneDriveCopyToUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.OneDrive.Read
    .DESCRIPTION
        Returns the state of a OneDrive copy started by ExecOneDriveCopyToUser: overall and per recipient (Queued, InProgress, Completed or Failed), with the number of files and bytes copied and any errors. Completed and Failed are final. SharePoint is checked at most once a minute per operation and for at most 100 unfinished copy jobs per call; within that minute the stored state is returned. Remove the leaver's licences only once State is Completed.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter
    $OperationId = $Request.Query.OperationId
    $StatusCode = [HttpStatusCode]::OK

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw [System.ArgumentException]::new('tenantFilter is required.') }
        if ([string]::IsNullOrWhiteSpace($OperationId)) { throw [System.ArgumentException]::new('OperationId is required.') }

        $Result = Update-CIPPOneDriveCopyToUserStatus -TenantFilter $TenantFilter -OperationId $OperationId
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "OneDrive copy status $OperationId -> $($Result.State)" -sev Debug
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
