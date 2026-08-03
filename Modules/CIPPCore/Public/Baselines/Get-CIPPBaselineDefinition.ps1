function Get-CIPPBaselineDefinition {
    <#
    .SYNOPSIS
        Returns the Baseline definition catalog: the standards available to add to a baseline.
    .DESCRIPTION
        One definition file per standard at Config/BaselineStandards/<category>/<Name>.json (design
        doc §5; rooted under Config because the module build ships only compiled psm1 files -
        Config is where runtime data files live, like intuneCollection.json). Each file carries
        the frontend metadata slice (label, category, help and executive text, recommended-by,
        impact, Secure Score impact, configurable variables) and the backend spec the engine
        executes: read (CIPPDb cacheType + optional path/select), expected (%var% template),
        remediate (typed executor), and the custom escape hatch.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Name)

    $DefinitionsPath = Join-Path $env:CIPPRootPath 'Config/BaselineStandards'
    $Files = Get-ChildItem -Path $DefinitionsPath -Filter '*.json' -Recurse -ErrorAction SilentlyContinue
    if ($Name) {
        $Files = $Files | Where-Object { $_.BaseName -eq $Name }
    }

    foreach ($File in $Files) {
        try {
            [System.IO.File]::ReadAllText($File.FullName) | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Information "Get-CIPPBaselineDefinition: failed to parse $($File.Name): $($_.Exception.Message)"
        }
    }
}
