function Send-CIPPRealtimeEvent {
    <#
    .SYNOPSIS
    Tell the users watching a job that it changed

    .DESCRIPTION
    Sends an event for a job id to every user granted it by Add-CIPPRealtimeWatch, carrying the changed
    data when given; without data their browser re-reads the job through the normal API. Safe from any
    worker. Does nothing outside CIPP-NG.

    .PARAMETER JobId
    The job id (a GUID)

    .PARAMETER Mode
    start, update or end

    .PARAMETER Data
    What changed, in the shape the job's list endpoint returns it

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [ValidateSet('start', 'update', 'end')]
        [string]$Mode = 'update',

        $Data
    )

    if ($env:CIPPNG -ne 'true') { return }
    try {
        [Craft.Services.RealtimeBridge]::Notify($JobId, $Mode, $Data)
    } catch {
        Write-Verbose "Realtime event unavailable: $($_.Exception.Message)"
    }
}
