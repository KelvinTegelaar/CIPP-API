function ConvertTo-CIPPComplianceSetParams {
    <#
    .SYNOPSIS
        Transform a New-* compliance cmdlet param hash into a Set-* param hash.
    .DESCRIPTION
        The Set-* family of Microsoft Purview compliance cmdlets diverges from New-* in two consistent ways:
          - 'Name' is replaced by 'Identity'.
          - Location params (and the Labels param on Set-LabelPolicy) must be Add-prefixed because the
            underlying data model is incremental list updates, not full replacement.

        Used by every deploy endpoint and standard for DLP, Retention, Sensitivity Label, and SIT so all
        purview policy types share the same Set-call shape.
    .PARAMETER Params
        Hashtable already shaped for the New-* cmdlet (location-typed values normalized, allowlist-filtered).
    .PARAMETER Identity
        Identity of the existing object to update.
    .PARAMETER AddPrefixFields
        Names of fields that must be Add-prefixed for the Set-* cmdlet. Caller supplies the list because it
        varies by cmdlet (locations always; Labels also for Set-LabelPolicy; nothing for Set-Label / rule
        cmdlets / Set-DlpSensitiveInformationType).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Params,
        [Parameter(Mandatory)] [string] $Identity,
        [string[]] $AddPrefixFields = @()
    )

    $set = @{}
    foreach ($key in $Params.Keys) {
        if ($key -eq 'Name') { continue }
        $targetKey = if ($key -in $AddPrefixFields) { "Add$key" } else { $key }
        $set[$targetKey] = $Params[$key]
    }
    $set['Identity'] = $Identity
    return $set
}
