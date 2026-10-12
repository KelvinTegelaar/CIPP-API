function ConvertTo-CIPPAsyncDeploymentRow {
    <#
    .SYNOPSIS
    Shape a CacheAsyncDeployments row for the frontend

    .DESCRIPTION
    The row as Get-CIPPAsyncDeployment returns it and the live update pushes it: Steps parsed, the
    tenant alongside, and when the row last changed.

    .PARAMETER Row
    The table row

    .PARAMETER LastUpdate
    When the row last changed; defaults to the row's Timestamp

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Row,

        $LastUpdate = $Row.Timestamp
    )

    [PSCustomObject]@{
        Name         = $Row.RowKey
        Source       = $Row.Source
        Status       = $Row.Status
        TaskId       = $Row.TaskId
        # Offboarding rows are users, so the tenant rides alongside; tenant-keyed jobs leave it empty
        TenantFilter = $Row.TenantFilter
        Steps        = @($Row.Steps | ConvertFrom-Json)
        Logs         = $Row.Logs
        # lets callers detect abandoned jobs
        LastUpdate   = $LastUpdate
    }
}
