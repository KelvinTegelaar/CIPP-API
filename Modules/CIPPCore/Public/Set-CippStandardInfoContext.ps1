function Set-CippStandardInfoContext {
    <#
    .SYNOPSIS
        Stores standard execution info in CIPPCore module-scoped AsyncLocal storage for the current invocation.
    .DESCRIPTION
        Used by standards entrypoints (e.g. Push-CIPPStandard in CIPPActivityTriggers) so that CIPPCore functions
        like Write-LogMessage and Set-CIPPStandardsCompareField can read the standard context. Module script scope
        is used instead of global scope, which is not reliable in Azure Functions.
    .PARAMETER StandardInfo
        Hashtable with Standard, StandardTemplateId, and optional IntuneTemplateId/ConditionalAccessTemplateId. Pass $null to clear.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $StandardInfo
    )

    if (-not $script:CippStandardInfoStorage) {
        $script:CippStandardInfoStorage = [System.Threading.AsyncLocal[object]]::new()
    }
    $script:CippStandardInfoStorage.Value = $StandardInfo
}
