function Invoke-ListIntuneDeploymentStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists the per-device and per-user deployment status of one Intune app, policy or script, like the Device status and User status pages in Intune. Devices or Users is null when Intune has no status for that side of the object type.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Id of the app, policy or script
    $Id = $Request.Query.ID
    # Graph collection of the object: mobileApps, configurationPolicies, deviceCompliancePolicies, deviceManagementScripts, an app protection type, ...
    $Type = $Request.Query.Type

    # The id goes into OData filters and URLs, so only id characters are accepted (app protection ids look like T_<guid>)
    if ([string]::IsNullOrWhiteSpace($Type) -or "$Id" -notmatch '^[A-Za-z0-9_-]+$') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'A valid ID and Type are required.' }
            })
    }

    try {
        $Results = Get-CIPPIntuneDeploymentStatus -TenantFilter $TenantFilter -Type $Type -Id $Id
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = $_.Exception.Message }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })
}
