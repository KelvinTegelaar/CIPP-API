function Invoke-ExecCippGroupReplacemap {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Groups.ReadWrite
    .SYNOPSIS
        Lists, adds, edits or deletes a tenant group's custom variables.
    .DESCRIPTION
        Group variables apply to every tenant in the group, between global and per-tenant values. They are part
        of the group, so they are managed with the tenant group permission rather than the per-tenant one.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # The group, as group:<groupId>.
    $TenantId = $Request.Query.tenantId ?? $Request.Body.tenantId
    # List, AddEdit or Delete.
    $Action = $Request.Query.Action ?? $Request.Body.Action
    if ($TenantId -notlike 'group:*' -or $Action -notin @('List', 'AddEdit', 'Delete')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'This endpoint only manages tenant group variables: send tenantId group:<groupId> and Action List, AddEdit or Delete.' }
            })
    }

    Invoke-ExecCippReplacemap -Request $Request -TriggerMetadata $TriggerMetadata
}
