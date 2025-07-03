using namespace System.Net

function Invoke-RemoveQueuedApp {
    <#
    .SYNOPSIS
    Remove a queued application from the CIPP apps table
    
    .DESCRIPTION
    Removes a queued application entry from the CIPP apps table by its unique ID, with logging and error handling.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
        
    .NOTES
    Group: Application Management
    Summary: Remove Queued App
    Description: Removes a queued application entry from the CIPP apps table by its unique ID, with logging and error handling for success or failure.
    Tags: Applications,Queue,Remove
    Parameter: ID (string) [body] - Unique identifier of the application to remove
    Response: Returns an object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: { "Results": "Removed application queue for [ID]." } with HTTP 200 status
    Response: On error: { "Results": "Failed to remove application queue for [ID]. [error details]" } with HTTP 403 status
    Example: {
      "Results": "Removed application queue for 12345678-1234-1234-1234-123456789012."
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $ID = $request.body.ID
    try {
        $Table = Get-CippTable -tablename 'apps'
        $Filter = "PartitionKey eq 'apps' and RowKey eq '$ID'"
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
        Remove-AzDataTableEntity -Force @Table -Entity $ClearRow
        $Message = "Removed application queue for $ID."
        Write-LogMessage -Headers $Request.Headers -API $APIName -message $Message -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to remove application queue for $ID. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -message $Message -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $body = [pscustomobject]@{'Results' = $Message }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })


}
