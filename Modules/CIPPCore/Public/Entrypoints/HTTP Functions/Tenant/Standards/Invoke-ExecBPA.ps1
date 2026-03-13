function Invoke-ExecBPA {
    <#
        .FUNCTIONALITY
        Entrypoint,AnyTenant
        .ROLE
        Tenant.BestPracticeAnalyser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ? $Request.Query.tenantFilter.value : $Request.Body.tenantfilter.value

    # Start the orchestrator - it will handle queuing internally
    Start-BPAOrchestrator -TenantFilter $TenantFilter -Force

    $Results = [pscustomobject]@{'Results' = 'BPA queued for execution' }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
