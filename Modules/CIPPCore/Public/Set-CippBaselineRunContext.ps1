function Set-CippBaselineRunContext {
    <#
    .SYNOPSIS
        Stores the baseline run id in CIPPCore module-scoped AsyncLocal storage for the current invocation.
    .DESCRIPTION
        Used by the baseline engine (Push-CIPPBaselineStandard and the orchestrator starter) so
        that Write-LogMessage stamps every log entry with the run's BaselineRunId column -
        ListLogs can then filter the logs to one exact run. Mirrors Set-CippScheduledTaskContext:
        module script scope is used instead of global scope, which is not reliable in Azure
        Functions.
    .PARAMETER RunId
        The baseline run GUID. Pass $null or empty to clear.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$RunId
    )

    if (-not $script:CippBaselineRunIdStorage) {
        $script:CippBaselineRunIdStorage = [System.Threading.AsyncLocal[string]]::new()
    }
    $script:CippBaselineRunIdStorage.Value = $RunId
}
