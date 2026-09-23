function Get-CIPPBecHeuristics {
    <#
    .SYNOPSIS
        Loads the BEC detection heuristics from Config\BecHeuristics.json.
    .DESCRIPTION
        Returns the parsed heuristics object (regexes, thresholds, caps and score weights) used by the
        BEC collectors and the server-side threat score. The delegated permission names from
        Config\RiskyPermissions.json are merged into riskyScopes.catalogNames so a grant is flagged by
        the curated catalog as well as by the regex. Read once per run.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Heuristics = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\BecHeuristics.json')) | ConvertFrom-Json -ErrorAction Stop

    $CatalogNames = try {
        $RiskyPermissions = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\RiskyPermissions.json')) | ConvertFrom-Json -ErrorAction Stop
        @($RiskyPermissions | Where-Object { $_.type -eq 'Delegated' -and $_.name } | ForEach-Object { $_.name } | Select-Object -Unique)
    } catch {
        Write-Information "BEC heuristics: could not merge RiskyPermissions.json: $($_.Exception.Message)"
        @()
    }
    $Heuristics.riskyScopes | Add-Member -NotePropertyName 'catalogNames' -NotePropertyValue $CatalogNames -Force
    return $Heuristics
}
