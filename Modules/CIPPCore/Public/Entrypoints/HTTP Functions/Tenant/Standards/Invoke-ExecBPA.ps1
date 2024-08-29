function Invoke-ExecBPA {
    <#
        .FUNCTIONALITY
        Entrypoint
        .ROLE
        Tenant.BestPracticeAnalyser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Start-BPAOrchestrator -TenantFilter $Request.Query.TenantFilter

    $Results = [pscustomobject]@{'Results' = 'BPA started' }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}
