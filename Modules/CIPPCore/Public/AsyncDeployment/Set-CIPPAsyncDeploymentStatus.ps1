function Set-CIPPAsyncDeploymentStatus {
    <#
    .SYNOPSIS
    Update the overall status of an async deployment row

    .DESCRIPTION
    Sets the overall status (and optionally the logs) of a CacheAsyncDeployments row created
    by New-CIPPAsyncDeployment.

    .PARAMETER JobId
    The deployment job id

    .PARAMETER Name
    The row name (typically the tenant)

    .PARAMETER Status
    queued, running, succeeded or failed

    .PARAMETER Logs
    Optional log text stored on the row
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('queued', 'running', 'succeeded', 'failed')]
        [string]$Status,

        $Logs
    )

    try {
        $Table = Get-CIPPTable -TableName 'CacheAsyncDeployments'
        $SafeJobId = $JobId -replace "'", "''"
        $SafeName = $Name -replace "'", "''"
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeJobId' and RowKey eq '$SafeName'"
        if (-not $Row) { return }

        $Row.Status = $Status
        if ($null -ne $Logs) { $Row.Logs = [string]$Logs }
        Add-CIPPAzDataTableEntity @Table -Entity $Row -Force
    } catch {
        Write-Verbose "Failed to update async deployment status: $($_.Exception.Message)"
    }
}
