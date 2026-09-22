function Invoke-ListAsyncDeployment {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.Read
    .SYNOPSIS
        Get the live progress of a background job
    .DESCRIPTION
        Returns the status rows of a background job that reports progress while it runs, such as a
        user offboarding started from the wizard: one row per target (the user) with its overall
        status and the status and message of every step.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # The job id handed back when the work was queued (e.g. DeploymentId from ExecOffboardUser)
    $DeploymentId = $Request.Query.DeploymentId ?? $Request.Body.DeploymentId
    if (-not $DeploymentId) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'DeploymentId is required' }
            })
    }

    # Rows name their tenant (TenantFilter, or Name for tenant-keyed jobs such as SharePoint template
    # deployments); a tenant-restricted caller only gets rows in scope.
    $Rows = @(Get-CIPPAsyncDeployment -JobId $DeploymentId | Select-CippAllowedTenantData -TenantProperty @('TenantFilter', 'Name'))
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 10 -InputObject $Rows
        })
}
