function Invoke-ExecCippGlobalReplacemap {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.GlobalVariables.ReadWrite
    .SYNOPSIS
        Adds, edits or deletes global custom variables.
    .DESCRIPTION
        Global variables apply to every tenant, so they are changed through this endpoint and its own
        permission, separate from the per-tenant custom variables managed through ExecCippReplacemap.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Must be AllTenants: this endpoint only changes global variables.
    $TenantId = $Request.Query.tenantId ?? $Request.Body.tenantId
    # AddEdit or Delete.
    $Action = $Request.Query.Action ?? $Request.Body.Action
    if ($TenantId -ne 'AllTenants' -or $Action -notin @('AddEdit', 'Delete')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'This endpoint only adds, edits or deletes global variables: send tenantId AllTenants and Action AddEdit or Delete.' }
            })
    }

    Invoke-ExecCippReplacemap -Request $Request -TriggerMetadata $TriggerMetadata
}
