function Get-CippGraphEndpointLabel {
    <#
    .SYNOPSIS
        Reduces a Graph endpoint to a stable label for egress accounting.
    .DESCRIPTION
        Drops the query string and version prefix and replaces id-like segments (GUIDs, UPNs,
        numbers, key or function arguments) with {id}, so users/<guid>/memberOf and users/<upn>/memberOf
        account as one endpoint: users/{id}/memberOf.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CippGraphEndpointLabel -Endpoint '/beta/users/2c1a.../memberOf?$top=5'
    #>
    [CmdletBinding()]
    param([string]$Endpoint)

    $Path = ($Endpoint -split '\?', 2)[0].Trim().Trim('/')
    $Path = $Path -replace '^(?i)(v1\.0|beta)/', ''
    if (-not $Path) { return $null }

    $Segments = foreach ($Segment in $Path.Split('/')) {
        $Segment = $Segment -replace '\(.*\)$', '({id})'
        if ($Segment -match '^[0-9a-fA-F-]{36}$|@|^\d+$') { '{id}' } else { $Segment }
    }
    return $Segments -join '/'
}
