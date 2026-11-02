function Set-CippBecCaseContext {
    <#
    .SYNOPSIS
        Stores the BEC case id in CIPPCore module-scoped AsyncLocal storage for the current invocation.
    .DESCRIPTION
        Used by the BEC check, containment, content search and evidence export so that Write-LogMessage
        stamps every log entry written while they run with a BecCaseId column. The evidence package
        bundles the logbook rows of a case by filtering on that column. Mirrors
        Set-CippBaselineRunContext / Set-CippScheduledTaskContext: module script scope is used instead
        of global scope, which is not reliable in Azure Functions.
    .PARAMETER CaseId
        The BEC case id. Pass $null or empty to clear.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$CaseId
    )

    if (-not $script:CippBecCaseIdStorage) {
        $script:CippBecCaseIdStorage = [System.Threading.AsyncLocal[string]]::new()
    }
    $script:CippBecCaseIdStorage.Value = $CaseId
}
