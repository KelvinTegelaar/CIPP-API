function Get-CippMcpSpec {
    <#
    .SYNOPSIS
        Loads and caches the CIPP OpenAPI specification (openapi.json).
    .DESCRIPTION
        Returns the parsed OpenAPI document used to project the MCP tool list. The result
        is cached per worker runspace; pass -Force to reload (e.g. after the spec is
        regenerated). Not an HTTP entrypoint.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if ($script:CippMcpSpec -and -not $Force) {
        return $script:CippMcpSpec
    }

    $Root = $env:CIPPRootPath
    if (-not $Root -or -not (Test-Path (Join-Path $Root 'openapi.json'))) {
        # Fallback: walk up from this module until openapi.json is found.
        $Root = $PSScriptRoot
        while ($Root -and -not (Test-Path (Join-Path $Root 'openapi.json'))) {
            $Parent = Split-Path $Root -Parent
            if (-not $Parent -or $Parent -eq $Root) { $Root = $null; break }
            $Root = $Parent
        }
    }

    $SpecPath = if ($Root) { Join-Path $Root 'openapi.json' } else { $null }
    if (-not $SpecPath -or -not (Test-Path $SpecPath)) {
        throw [pscustomobject]@{ code = -32603; message = 'OpenAPI spec (openapi.json) not found; cannot project MCP tools.' }
    }

    # -AsHashtable is required: the spec contains objects with case-differing keys
    # (e.g. displayName / DisplayName) which a case-insensitive PSCustomObject cannot hold.
    $script:CippMcpSpec = [System.IO.File]::ReadAllText($SpecPath) | ConvertFrom-Json -AsHashtable -Depth 100
    return $script:CippMcpSpec
}
