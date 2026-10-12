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

    # Definition files ship with the app, so they are listed and read once per worker; each call still parses fresh objects.
    $script:CippBaselineDefinitionText ??= @{}
    if (-not $script:CippBaselineDefinitionFiles) {
        $DefinitionsPath = Join-Path $env:CIPPRootPath 'Config/BaselineStandards'
        $script:CippBaselineDefinitionFiles = @(Get-ChildItem -Path $DefinitionsPath -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    $Files = $script:CippBaselineDefinitionFiles
    if ($Name) {
        $Files = $Files.Where({ [System.IO.Path]::GetFileNameWithoutExtension($_) -eq $Name })
    }

    foreach ($File in $Files) {
        try {
            $script:CippBaselineDefinitionText[$File] ??= [System.IO.File]::ReadAllText($File)
            $script:CippBaselineDefinitionText[$File] | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Information "Get-CIPPBaselineDefinition: failed to parse $([System.IO.Path]::GetFileName($File)): $($_.Exception.Message)"
        }
    }
}
