function Test-CIPPGroupIsExchangeBacked {
    <#
    .SYNOPSIS
    Decides whether a group selected in a form must be changed through Exchange rather than Graph.

    .DESCRIPTION
    $ResolvedType is what Graph/Exchange says the group is and always wins. The fields on the
    autocomplete option are only a fallback: they are missing on older saved selections and stale
    on any group converted since. In calculatedGroupType, 'security' means a MAIL-ENABLED security
    group (Exchange) while a plain security group is 'generic' (Graph).

    .FUNCTIONALITY
        Internal
    #>
    param($AddedFields, $ResolvedType)
    if ($ResolvedType) {
        return $ResolvedType -in @('Distribution List', 'Mail-Enabled Security')
    }
    $Calculated = $AddedFields.calculatedGroupType
    if ($Calculated) {
        return $Calculated -in @('distributionList', 'security')
    }
    return $AddedFields.groupType -in @('Distribution List', 'Mail-Enabled Security', 'distributionList')
}
