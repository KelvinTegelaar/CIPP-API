function Invoke-ExecSharePointPermissionsSync {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Reports.ReadWrite
    .SYNOPSIS
        Start a SharePoint permissions report sync
    .DESCRIPTION
        Queues a refresh of one of the cached datasets the SharePoint permissions report is built from, for a single tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    if ($Request.Query.tenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'The permissions report sync runs against a single tenant' } })
    }

    # The cached dataset to refresh.
    switch ($Request.Query.Name) {
        'SharePointPermissions' {}
        default {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "'$($Request.Query.Name)' is not a permissions report dataset" } })
        }
    }

    $ForwardRequest = @{
        Params  = $Request.Params
        Headers = $Request.Headers
        Query   = @{ TenantFilter = $Request.Query.tenantFilter; Name = $Request.Query.Name }
    }

    return Invoke-ExecCIPPDBCache -Request $ForwardRequest -TriggerMetadata $TriggerMetadata
}
