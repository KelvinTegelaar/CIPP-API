function Invoke-ExecAppUpload {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        # Start the orchestrator directly - it handles queuing internally
        Start-ApplicationOrchestrator
        $Results = [pscustomobject]@{'Results' = 'Application upload job has started. Track the logbook for results.' }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to start application upload. Error: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
