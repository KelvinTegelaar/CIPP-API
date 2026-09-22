function New-CIPPAsyncDeployment {
    <#
    .SYNOPSIS
    Create a trackable async deployment job

    .DESCRIPTION
    Creates one status row per deployment target in the CacheAsyncDeployments table so a
    frontend can poll live progress (rendered by CippApiResults' jobProgress option). Each
    row starts as queued with every step pending. Update progress with
    Set-CIPPAsyncDeploymentStep / Set-CIPPAsyncDeploymentStatus and read it back with
    Get-CIPPAsyncDeployment.

    .PARAMETER JobId
    The job id shared by all rows. Generated when not provided.

    .PARAMETER Names
    One row is created per name — typically the target tenants.

    .PARAMETER StepTitles
    Ordered steps shown to the user (e.g. one per site template): a title string, or an object with
    Title plus an optional Kind (e.g. 'notify', which the UI does not offer for step re-run) and an
    initial Message. Optional, so a row can be created as soon as work is queued and given its steps
    later by calling this again with the same JobId and Name.

    .PARAMETER Source
    Which feature created this job (e.g. SharePointTemplate)

    .PARAMETER TenantFilter
    The tenant the rows belong to, when the names are not tenants themselves (offboarding rows are
    users). Stored on the row so restricted callers only see rows for tenants in their scope.

    .PARAMETER TaskId
    The ScheduledTasks RowKey behind the row(s), when the work runs as a scheduled task. Stored on
    the row so the UI can offer a re-run through the scheduler.
    #>
    [CmdletBinding()]
    param(
        [string]$JobId = (New-Guid).Guid,

        [Parameter(Mandatory = $true)]
        [string[]]$Names,

        [object[]]$StepTitles = @(),

        [string]$Source = 'CIPP',

        [string]$TaskId,

        [string]$TenantFilter
    )

    $Table = Get-CIPPTable -TableName 'CacheAsyncDeployments'
    $InitialSteps = [string](ConvertTo-Json -Compress -Depth 5 -InputObject @(
            $StepTitles | ForEach-Object {
                if ($_ -is [string]) {
                    @{
                        Title   = [string]$_
                        Status  = 'pending'
                        Message = 'Waiting to start'
                    }
                } else {
                    @{
                        Title   = [string]$_.Title
                        Status  = 'pending'
                        Message = [string]($_.Message ?? 'Waiting to start')
                        Kind    = [string]$_.Kind
                    }
                }
            }
        ))

    foreach ($Name in $Names) {
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = [string]$JobId
            RowKey       = [string]$Name
            Source       = [string]$Source
            Status       = 'queued'
            Steps        = $InitialSteps
            TaskId       = [string]$TaskId
            TenantFilter = [string]$TenantFilter
            Logs         = ''
        } -Force
    }
    return $JobId
}
