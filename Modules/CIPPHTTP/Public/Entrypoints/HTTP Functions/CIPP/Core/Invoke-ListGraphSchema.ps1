function Invoke-ListGraphSchema {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Describes what a Microsoft Graph endpoint returns without calling it: the entity type
        behind the path, every property with its type, and the navigation properties that can
        be expanded or traversed. Use it to check whether an endpoint carries the field you
        need before spending a request on it - particularly before an AllTenants run, where a
        single call is multiplied by the tenant count. Answers come from the Graph metadata
        shipped with CIPP, so no tenant is contacted and no permissions are required.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # The Graph path to describe, e.g. 'users', 'groups/{id}/members', or a full Graph URL.
    $Endpoint = $Request.Query.Endpoint ?? $Request.Body.Endpoint
    # Which Graph API version to resolve against: 'beta' (default) or 'v1.0'.
    $Version = $Request.Query.Version ?? $Request.Body.Version ?? 'beta'

    if (-not $Endpoint) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "The 'Endpoint' parameter is required, e.g. Endpoint=users or Endpoint=groups/{id}/members." }
            })
    }

    if ($Version -notin @('v1.0', 'beta')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Version must be 'v1.0' or 'beta'." }
            })
    }

    try {
        $Schema = Get-CippGraphSchema -Endpoint $Endpoint -Version $Version
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        # An unknown entity set or navigation property is a caller mistake, and the message
        # from the resolver lists what was available, so it is worth returning verbatim.
        $Schema = @{ Results = $_.Exception.Message }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Schema
        })
}
