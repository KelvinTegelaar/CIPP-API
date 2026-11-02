function Invoke-CIPPBaselineDeleteIntunePolicy {
    <#
    .SYNOPSIS
        Delete executor: removes one Intune policy an operator explicitly denied.
    .DESCRIPTION
        Called by the engine ONLY for a per-path deny verdict (verdict 'denyDelete') on
        a detect-drift standard - never for untriaged drift, and never in compare mode.
        The target is the resolved row's current value at that path, carrying the policy
        id and its Graph collection segment (the same segment the RemovePolicy endpoint
        deletes through). Throws on failure so the engine records the error and keeps the
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
    $Resource = "$($Target.resource)"
    if (-not $PolicyId) { throw 'The denied policy carries no id - nothing to delete.' }
    if (-not $Resource) { throw "The denied policy '$PolicyId' carries no Graph resource path - nothing to delete." }

    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/$Resource('$PolicyId')" -type DELETE -tenantid $TenantFilter
}
