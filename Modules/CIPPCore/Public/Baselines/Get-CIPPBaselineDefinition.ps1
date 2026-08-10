function Get-CIPPBaselineDefinition {
    <#
    .SYNOPSIS
        Returns the Baseline definition catalog: the standards available to add to a baseline.
    .DESCRIPTION
        One definition file per standard at Config/BaselineStandards/<category>/<Name>.json.
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
