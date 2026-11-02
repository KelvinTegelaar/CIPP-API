function Start-CIPPBecIPReviewJob {
    <#
    .SYNOPSIS
        Queues a BEC IP review as a background scheduled task with live progress.
    .DESCRIPTION
        The background path of ExecBECIPReview, shaped like containment: creates the progress row so the
        caller can poll at once, then queues Invoke-CIPPBecIPReview as a run-now scheduled task that fills
        it with one step per stage. Returns the DeploymentId to poll with ListOffboardingProgress.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER CaseId
        The BEC case to review.
    .PARAMETER Overrides
        The validated overrides ({ IP, Verdict, Note }).
    .PARAMETER CorrelateUserIds
        Object ids of accounts to correlate.
    .PARAMETER UserPrincipalName
        The investigated user (for the task name).
    .PARAMETER Headers
        The requesting user's headers.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [object[]]$Overrides = @(),
        [string[]]$CorrelateUserIds = @(),
        [string]$UserPrincipalName,
        $Headers
    )

    if (-not $PSCmdlet.ShouldProcess("$TenantFilter/$CaseId", 'Queue BEC IP review')) { return }
    $DeploymentId = New-CIPPAsyncDeployment -Names @($CaseId) -Source 'BECIPReview' -TenantFilter $TenantFilter
    $Task = [pscustomobject]@{
        TenantFilter = $TenantFilter
        Name         = "BEC IP review: $(if ($UserPrincipalName) { $UserPrincipalName } else { $CaseId })"
        Command      = @{ value = 'Invoke-CIPPBecIPReview' }
        Parameters   = [pscustomobject]@{
            CaseId           = $CaseId
            Overrides        = @($Overrides)
            CorrelateUserIds = @($CorrelateUserIds)
            DeploymentId     = $DeploymentId
            APIName          = 'BECIPReview'
        }
    }
    # the scheduler reports a refused task as a returned 'Error - ...' string, not a throw
    $Queued = Add-CIPPScheduledTask -Task $Task -hidden $false -RunNow -Headers $Headers
    if ([string]$Queued -match '^(Error|Could not)') {
        Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $CaseId -Status 'failed'
        throw [string]$Queued
    }
    return $DeploymentId
}
