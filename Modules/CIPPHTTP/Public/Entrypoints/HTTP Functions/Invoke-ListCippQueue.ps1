function Invoke-ListCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists active and recent CIPP background processing queue items and their status.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message 'Accessed this API' -Sev 'Debug'

    $QueueData = Get-CIPPQueueData -Request $Request -TriggerMetadata $TriggerMetadata

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($QueueData)
        })
}
