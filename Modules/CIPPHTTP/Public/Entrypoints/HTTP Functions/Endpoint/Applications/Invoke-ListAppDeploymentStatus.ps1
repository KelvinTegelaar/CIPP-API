function Invoke-ListAppDeploymentStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.Read
    .DESCRIPTION
        Lists the per-device and per-user install status of one Intune app, like the Device install status and User install status pages in Intune. Same response as ListIntuneDeploymentStatus, readable with application permissions only.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Application readers may only reach the app branch of the shared handler
    $Forwarded = [pscustomobject]@{
        Params  = $Request.Params
        Headers = $Request.Headers
        Query   = [pscustomobject]@{
            tenantFilter = $Request.Query.tenantFilter
            # Id of the app
            ID           = $Request.Query.ID
            Type         = 'mobileApps'
        }
    }
    Invoke-ListIntuneDeploymentStatus -Request $Forwarded -TriggerMetadata $TriggerMetadata
}
