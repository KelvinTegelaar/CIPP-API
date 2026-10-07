function Invoke-CIPPBaselineDeleteCAPolicy {
    <#
    .SYNOPSIS
        Delete executor: removes one Conditional Access policy an operator explicitly denied.
    .DESCRIPTION
        Called by the engine ONLY for a per-path deny verdict (verdict 'denyDelete') on
        the CA detect-drift standard - never for untriaged drift, and never in compare
        mode. Deletes through the same Graph call as the RemoveCAPolicy endpoint
        (app-only, v1.0). Throws on failure so the engine records the error and keeps the
        row pending instead of reporting a deletion that did not happen.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Target,
        $TenantFilter
    )

    $PolicyId = "$($Target.id)"
    if (-not $PolicyId) { throw 'The denied policy carries no id - nothing to delete.' }

    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$PolicyId" -type DELETE -tenantid $TenantFilter -AsApp $true
}
