function Set-CIPPAsyncDeploymentStep {
    <#
    .SYNOPSIS
    Update one step of an async deployment row

    .DESCRIPTION
    Sets the status and message of a single step on a CacheAsyncDeployments row created by
    New-CIPPAsyncDeployment. Safe to call from queue workers, including several at once for
    different steps of the same row; failures to persist are swallowed so status reporting
    never breaks the actual work.

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

    # Keep the row well inside the 64 KB property limit: a cmdlet that lists hundreds of groups
    # would otherwise make the whole write fail and freeze the progress view.
    if ($Message.Length -gt 2000) { $Message = $Message.Substring(0, 2000) + '...' }

    # All steps of a row live in one JSON property, and steps can run on different workers at the
    # same time. The write is ETag-checked (no -Force) so a step finishing between our read and
    # write is not overwritten; a rejected write re-reads the row and tries again.
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
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
            Update-CIPPAzDataTableEntity @Table -Entity $Row
            return
        } catch {
            Write-Verbose "Failed to update async deployment step (attempt $Attempt): $($_.Exception.Message)"
            Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 250)
        }
    }
}
