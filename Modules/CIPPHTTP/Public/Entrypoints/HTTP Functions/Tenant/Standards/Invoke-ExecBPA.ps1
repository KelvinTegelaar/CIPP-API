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

    # AnyTenant: the orchestrator runs outside this request's scope, so restricted callers
    # need a single in-scope tenant; Get-Tenants is narrowed to the caller's allowed tenants
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants' -or -not (Get-Tenants -TenantFilter $TenantFilter)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = [pscustomobject]@{'Results' = 'Access to this tenant is not allowed' }
                })
        }
    }

    # Start the orchestrator - it will handle queuing internally
    Start-BPAOrchestrator -TenantFilter $TenantFilter -Force

    $Results = [pscustomobject]@{'Results' = 'BPA queued for execution' }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
