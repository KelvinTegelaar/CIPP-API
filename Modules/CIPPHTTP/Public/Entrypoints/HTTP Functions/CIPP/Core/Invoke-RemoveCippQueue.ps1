function Invoke-RemoveCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint ?? 'RemoveCippQueue'
    $Headers = $Request.Headers

    try {
        $Results = Clear-CIPPQueueData -Request $Request -TriggerMetadata $TriggerMetadata
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message 'History cleared' -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to clear queue history: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results = @{Results = @("Failed to clear queue history: $($ErrorMessage.NormalizedError)") }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}
