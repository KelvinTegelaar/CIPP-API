function Set-CIPPAsyncDeploymentStep {
    <#
    .SYNOPSIS
    Update one step of an async deployment row

    .DESCRIPTION
    Sets the status and message of a single step on a CacheAsyncDeployments row created by
    New-CIPPAsyncDeployment. Safe to call from queue workers; failures to persist are
    swallowed so status reporting never breaks the actual deployment.

    .PARAMETER JobId
    The deployment job id

    .PARAMETER Name
    The row name (typically the tenant)

    .PARAMETER StepIndex
    Zero-based index of the step to update

    .PARAMETER StepStatus
    pending, running, succeeded or failed

    .PARAMETER Message
    Progress message shown under the step title
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$StepIndex,

        [Parameter(Mandatory = $true)]
        [ValidateSet('pending', 'running', 'succeeded', 'failed')]
        [string]$StepStatus,

        [string]$Message = ''
    )

    try {
        $Table = Get-CIPPTable -TableName 'CacheAsyncDeployments'
        $SafeJobId = $JobId -replace "'", "''"
        $SafeName = $Name -replace "'", "''"
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeJobId' and RowKey eq '$SafeName'"
        if (-not $Row) { return }

        $Steps = @($Row.Steps | ConvertFrom-Json)
        if ($StepIndex -lt 0 -or $StepIndex -ge $Steps.Count) { return }
        $Steps[$StepIndex].Status = $StepStatus
        $Steps[$StepIndex].Message = $Message
        $Row.Steps = [string](ConvertTo-Json -InputObject @($Steps) -Compress -Depth 5)
        Add-CIPPAzDataTableEntity @Table -Entity $Row -Force
    } catch {
        Write-Verbose "Failed to update async deployment step: $($_.Exception.Message)"
    }
}
