function Add-CIPPRealtimeWatch {
    <#
    .SYNOPSIS
    Grant the signed-in caller live events for a job

    .DESCRIPTION
    Registers the user behind the current HTTP request with Craft's realtime channel for a job id, so
    events for it reach their browser over /.craft/events. With -Run, Craft also pushes the
    orchestrator run status for that queue id itself. Does nothing outside CIPP-NG or outside an HTTP
    request, so callers never need to check either.

    .PARAMETER JobId
    The job or queue id (a GUID)

    .PARAMETER Run
    Have Craft push the run status of this queue id until it finishes

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JobId,

        [switch]$Run
    )

    if ($env:CIPPNG -ne 'true' -or -not $script:CippRealtimeUser) { return }
    try {
        if ($Run) {
            [Craft.Services.RealtimeBridge]::WatchRun($script:CippRealtimeUser, $JobId)
        } else {
            [Craft.Services.RealtimeBridge]::Watch($script:CippRealtimeUser, $JobId)
        }
    } catch {
        Write-Verbose "Realtime watch unavailable: $($_.Exception.Message)"
    }
}
