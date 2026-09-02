function Invoke-ListOffboardingProgress {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.ReadWrite
    .SYNOPSIS
        Get the live progress of an offboarding job
    .DESCRIPTION
        Returns the progress rows of an offboarding job started from the wizard: one row per user with
        its overall status and the status and message of every step. Same rows as ListAsyncDeployment,
        under the wizard's own permission so an offboarding operator can follow and re-run their jobs.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # The DeploymentId handed back by ExecOffboardUser, also stored on each offboarding task
    $DeploymentId = $Request.Query.DeploymentId
    if (-not $DeploymentId) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'DeploymentId is required' }
            })
    }

    # Rows carry the tenant they belong to; a tenant-restricted caller only gets rows in scope.
    $Rows = @(Get-CIPPAsyncDeployment -JobId $DeploymentId | Select-CippAllowedTenantData -TenantProperty @('TenantFilter', 'Name'))
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject $Rows
        })
}