Function Invoke-ListDeletedItems {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    # Interact with query parameters or the body of the request.
    $Types = 'Application', 'User', 'Group'
    $GraphRequest = foreach ($Type in $Types) {
    (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/deletedItems/microsoft.graph.$($Type)" -tenantid $TenantFilter) |
            Where-Object -Property '@odata.context' -NotLike '*graph.microsoft.com*' |
            Select-Object *, @{ Name = 'TargetType'; Expression = { $Type } }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })
}
