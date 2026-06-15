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
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to start application upload. Error: $($_.Exception.Message)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
