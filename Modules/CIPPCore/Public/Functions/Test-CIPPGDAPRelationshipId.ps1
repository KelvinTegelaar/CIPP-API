function Test-CIPPGDAPRelationshipId {
    <#
    .SYNOPSIS
        Tests if a string is a GDAP relationship id
    .DESCRIPTION
        A delegated admin relationship id is two GUIDs joined by a hyphen. Endpoints place it in a
        Graph URL, so anything else is refused.
    .PARAMETER Id
        The string to test
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Id
    )

    return $Id.Length -eq 73 -and $Id[36] -eq '-' -and (Test-IsGuid -String $Id.Substring(0, 36)) -and (Test-IsGuid -String $Id.Substring(37))
}
