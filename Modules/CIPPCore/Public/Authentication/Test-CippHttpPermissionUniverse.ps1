function Test-CippHttpPermissionUniverse {
    <#
    .SYNOPSIS
        Decides whether a list of permission names can be the full HTTP permission universe.
    .DESCRIPTION
        The universe is every distinct .ROLE across the HTTP entrypoints - well over a hundred
        names shaped Area.Object.Read/ReadWrite, always including the core read permission the
        dashboard needs. A list that is short, contains non-permission text, or lacks the core
        permission came from a failed or truncated enumeration.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Permissions
    )

    $Names = @($Permissions | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Names.Count -lt 50) { return $false }
    if ($Names -notcontains 'CIPP.Core.Read') { return $false }
    foreach ($Name in $Names) {
        if ($Name -ne 'None' -and $Name -notmatch '^[A-Za-z0-9]+\.[A-Za-z0-9]+\.[A-Za-z]+$') { return $false }
    }
    return $true
}
