function Get-CIPPAsyncDeployment {
    <#
    .SYNOPSIS
    Get the status rows of an async deployment job

    .DESCRIPTION
    Returns all CacheAsyncDeployments rows for a job id with the Steps JSON parsed, in the
    shape the frontend jobProgress option of CippApiResults renders (Name, Status, Steps,
    Logs).

    .PARAMETER JobId
    The deployment job id
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId
    )

    $Table = Get-CIPPTable -TableName 'CacheAsyncDeployments'
    $SafeJobId = $JobId -replace "'", "''"
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeJobId'"

    @($Rows | ForEach-Object {
            [PSCustomObject]@{
                Name   = $_.RowKey
                Source = $_.Source
                Status = $_.Status
                TaskId = $_.TaskId
                # Offboarding rows are users, so the tenant rides alongside; tenant-keyed jobs leave it empty
                TenantFilter = $_.TenantFilter
                Steps  = @($_.Steps | ConvertFrom-Json)
                Logs   = $_.Logs
            }
        })
}
