function Add-CIPPAsyncDeploymentStep {
    <#
    .SYNOPSIS
    Append a step to an async deployment row

    .DESCRIPTION
    Adds a step, with its final status, to the end of a CacheAsyncDeployments row created by
    New-CIPPAsyncDeployment. Used for work that only exists once the job has finished, such as the
    post-execution notifications of an offboarding. Meant to be called after the parallel step
    workers are done; failures to persist are swallowed so reporting never breaks the job.

    .PARAMETER JobId
    The deployment job id

    .PARAMETER Name
    The row name (the user for offboarding, the tenant for tenant-keyed jobs)

    .PARAMETER Title
    Step title shown to the user

    .PARAMETER StepStatus
    pending, running, succeeded or failed

    .PARAMETER Message
    Progress message shown under the step title

    .PARAMETER Kind
    What kind of step this is, e.g. 'notify'. The UI offers a step re-run only for plain task steps.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [ValidateSet('pending', 'running', 'succeeded', 'failed')]
        [string]$StepStatus = 'succeeded',

        [string]$Message = '',

        [string]$Kind = ''
    )

    try {
        if ($Message.Length -gt 2000) { $Message = $Message.Substring(0, 2000) + '...' }
        $Table = Get-CIPPTable -TableName 'CacheAsyncDeployments'
        $SafeJobId = $JobId -replace "'", "''"
        $SafeName = $Name -replace "'", "''"
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeJobId' and RowKey eq '$SafeName'"
        if (-not $Row) { return }

        $Steps = @(
            @($Row.Steps | ConvertFrom-Json)
            [pscustomobject]@{ Title = $Title; Status = $StepStatus; Message = $Message; Kind = $Kind }
        )
        $Row.Steps = [string](ConvertTo-Json -InputObject @($Steps) -Compress -Depth 5)
        Update-CIPPAzDataTableEntity @Table -Entity $Row -Force
    } catch {
        Write-Verbose "Failed to append async deployment step: $($_.Exception.Message)"
    }
}
