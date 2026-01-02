function Start-DurableCleanup {
    <#
    .SYNOPSIS
    Start the durable cleanup process.

    .DESCRIPTION
    Look for orchestrators running for more than the specified time and terminate them. Also, clear any queues that have items for that function app.

    .PARAMETER MaxDuration
    The maximum duration an orchestrator can run before being terminated.

    .FUNCTIONALITY
    Internal
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [int]$MaxDuration = 86400
    )
    Write-Information "This cleanup is no longer required."
}
