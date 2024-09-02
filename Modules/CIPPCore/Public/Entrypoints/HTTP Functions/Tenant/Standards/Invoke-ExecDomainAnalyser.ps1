function Invoke-ExecDomainAnalyser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.DomainAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Start-DomainOrchestrator

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $results
        })
}
