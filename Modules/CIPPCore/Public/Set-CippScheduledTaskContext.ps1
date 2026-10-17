function Set-CippScheduledTaskContext {
    <#
    .SYNOPSIS
        Stores the scheduled task id in CIPPCore module-scoped AsyncLocal storage for the current invocation.
    .DESCRIPTION
        Used by the scheduler engine (Push-ExecScheduledCommand in CIPPActivityTriggers) so that CIPPCore functions
        like Write-LogMessage can attribute log entries to the running scheduled task. Module script scope
        is used instead of global scope, which is not reliable in Azure Functions.
    .PARAMETER TaskId
        The scheduled task RowKey. Pass $null or empty to clear.
    .PARAMETER AlertReNotify
        The alert task's re-notify setting, read by Write-AlertTrace. Reset on every call.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TaskId,
        [bool]$AlertReNotify
    )

    if (-not $script:CippScheduledTaskIdStorage) {
        $script:CippScheduledTaskIdStorage = [System.Threading.AsyncLocal[string]]::new()
    }
    $script:CippScheduledTaskIdStorage.Value = $TaskId
    if (-not $script:CippAlertReNotifyStorage) {
        $script:CippAlertReNotifyStorage = [System.Threading.AsyncLocal[bool]]::new()
    }
    $script:CippAlertReNotifyStorage.Value = $AlertReNotify
}
