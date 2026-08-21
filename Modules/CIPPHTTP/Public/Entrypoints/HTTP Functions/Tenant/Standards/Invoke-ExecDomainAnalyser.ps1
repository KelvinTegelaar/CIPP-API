function Invoke-ExecDomainAnalyser {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.DomainAnalyser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Call the wrapper - it handles queuing internally via Start-CIPPOrchestrator
    $Params = @{}
    if ($Request.Body.tenantFilter) {
        $Params.TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    }

    # AnyTenant: the orchestrator runs outside this request's scope, so restricted callers
    # need a single in-scope tenant; Get-Tenants is narrowed to the caller's allowed tenants
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        if (-not $Params.TenantFilter -or $Params.TenantFilter -eq 'AllTenants' -or -not (Get-Tenants -TenantFilter $Params.TenantFilter)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = [pscustomobject]@{'Results' = 'Access to this tenant is not allowed' }
                })
        }
    }

    $OrchStatus = Start-DomainOrchestrator @Params
    if ($OrchStatus) {
        $Message = 'Domain Analyser started'
    } else {
        $Message = 'Domain Analyser error: check logs'
    }
    $Results = [pscustomobject]@{'Results' = $Message }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}
