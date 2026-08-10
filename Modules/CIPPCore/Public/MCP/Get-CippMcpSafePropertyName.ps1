function Get-CippMcpSafePropertyName {
    <#
    .SYNOPSIS
        Maps a request parameter name onto one an MCP client will accept, or $null when it
        cannot be represented.
    .DESCRIPTION
        MCP tool input schemas may only use property names matching ^[a-zA-Z0-9_.-]{1,64}$.
        CIPP endpoints read OData system query options directly off the request
        ($Request.Query.'$filter'), so those names reach the projection with a leading $ and
        the client refuses the schema.

        '$filter' becomes 'odata_filter'. The prefix is used rather than simply stripping the
        $ because several endpoints expose BOTH forms - ListGraphRequest takes '$expand' (the
        OData option, passed to Graph) and 'expand' (a CIPP-specific flag) and they mean
        different things - so collapsing them would silently merge two parameters into one.

        Get-CippMcpToolCatalog records the mapping on the catalog entry as _paramAlias, and
        Invoke-CippMcpApiRequest reverses it before dispatching, so the endpoint still sees the
        name it actually reads.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        # Names already used by this schema; a rename must never shadow a real parameter.
        $Taken
    )

    if ([string]::IsNullOrEmpty($Name)) { return $null }
    if ($Name -cmatch '^[a-zA-Z0-9_.-]{1,64}$') { return $Name }

    $Candidate = if ($Name.StartsWith('$')) { 'odata_' + $Name.Substring(1) } else { $Name }
    $Candidate = $Candidate -replace '[^a-zA-Z0-9_.-]', '_'
    if ($Candidate.Length -gt 64) { $Candidate = $Candidate.Substring(0, 64) }
    if ($Candidate -notmatch '^[a-zA-Z0-9_.-]{1,64}$') { return $null }

    if ($Taken -and @($Taken) -contains $Candidate) { return $null }
    return $Candidate
}
