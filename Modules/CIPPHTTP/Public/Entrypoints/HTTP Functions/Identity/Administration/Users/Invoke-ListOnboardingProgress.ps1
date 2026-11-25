function Invoke-ListOnboardingProgress {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Get the live progress of a user onboarding job
    .DESCRIPTION
        Returns the progress rows of an onboarding job started from the wizard: one row per user with
        its overall status and the status and message of every step. Same rows and tenant scoping as
        ListOffboardingProgress.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # The DeploymentId handed back by ExecOnboardUser (also stored on the onboarding task)
    if (-not $Request.Query.DeploymentId) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'DeploymentId is required' }
            })
    }
    return (Invoke-ListOffboardingProgress -Request $Request -TriggerMetadata $TriggerMetadata)
}
