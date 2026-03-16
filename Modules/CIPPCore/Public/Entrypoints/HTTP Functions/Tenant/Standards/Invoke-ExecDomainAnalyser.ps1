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
