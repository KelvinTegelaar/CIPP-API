function Start-CIPPBecContainmentJob {
    <#
    .SYNOPSIS
        Queues BEC containment as a background scheduled task with live progress.
    .DESCRIPTION
        The background path of ExecBECRemediate, shaped like offboarding: creates the progress row
        (so the caller can poll straight away), then queues Invoke-CIPPBecContainment as a run-now
        scheduled task that fills the row with one step per action. The caller has already validated
        the selection and the typed confirmation, so the task runs with -Confirmed. Its stored results
        are the redacted rows; only the progress step messages carry a new password.
        Returns the DeploymentId to poll with ListOffboardingProgress.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$UserId,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][string[]]$Actions,
        $Parameters,
        [string]$CaseId,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    if (-not $PSCmdlet.ShouldProcess($UserPrincipalName, "Queue BEC containment ($($Actions -join ', '))")) { return }

    $DeploymentId = New-CIPPAsyncDeployment -Names @($UserPrincipalName) -Source 'BECRemediation' -TenantFilter $TenantFilter
    $Task = [pscustomobject]@{
        TenantFilter = $TenantFilter
        Name         = "BEC remediation: $UserPrincipalName"
        Command      = @{ value = 'Invoke-CIPPBecContainment' }
        Parameters   = [pscustomobject]@{
            UserId            = $UserId
            UserPrincipalName = $UserPrincipalName
            Actions           = @($Actions)
            Parameters        = $Parameters
            Confirmed         = $true
            Redacted          = $true
            CaseId            = $CaseId
            DeploymentId      = $DeploymentId
            APIName           = $APIName
        }
    }
    # the scheduler reports a refused task as a returned 'Error - ...' string, not a throw
    $Queued = Add-CIPPScheduledTask -Task $Task -hidden $false -RunNow -Headers $Headers
    if ([string]$Queued -match '^(Error|Could not)') {
        Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $UserPrincipalName -Status 'failed'
        throw [string]$Queued
    }
    return $DeploymentId
}
