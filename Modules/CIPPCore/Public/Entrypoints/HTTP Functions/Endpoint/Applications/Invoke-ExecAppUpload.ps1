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
        Start-ApplicationOrchestrator
    } catch {
        Write-Host "orchestrator error: $($_.Exception.Message)"
    }

    $Results = [pscustomobject]@{'Results' = 'Started application queue' }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $results
        })

}
