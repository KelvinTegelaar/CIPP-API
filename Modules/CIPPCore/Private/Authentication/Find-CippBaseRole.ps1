function Find-CippBaseRole {
    <#
    .SYNOPSIS
        The base-role property matching any of the given role names.
    .DESCRIPTION
        Preserves the original loop semantics: base-role properties are walked in
        definition order and a later match overwrites an earlier one.
    .FUNCTIONALITY
        Internal
    #>
    param($Roles, $BaseRoles)
    $BaseRole = $null
    foreach ($Role in $BaseRoles.PSObject.Properties) {
        foreach ($CandidateRole in $Roles) {
            if ($Role.Name -eq $CandidateRole) {
                $BaseRole = $Role
                break
            }
        }
    }
    return $BaseRole
}
