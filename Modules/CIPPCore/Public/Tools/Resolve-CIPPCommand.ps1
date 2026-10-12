function Resolve-CIPPCommand {
    <#
    .SYNOPSIS
        Resolves a function's exact name and owning module without importing that module.
    .DESCRIPTION
        Get-Command autoloads the module that exports a function, which pulls whole sibling modules
        (CIPPAlerts, CIPPStandards, CIPPDB, ...) into an HTTP worker just to validate a name. This checks
        the functions already loaded, then an index of the sibling module manifests' exports.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    # Get-Command autoloads even with -ListImported; the function: drive only sees what is loaded.
    $Loaded = Get-Item -LiteralPath "function:$Name" -ErrorAction SilentlyContinue
    if ($Loaded) { return [pscustomobject]@{ Name = $Loaded.Name; ModuleName = $Loaded.ModuleName } }

    if (-not $script:CIPPCommandIndex) {
        $Index = [System.Collections.Generic.Dictionary[string, System.Tuple[string, string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $ModuleDirs = if ($env:CIPPRootPath) { Get-ChildItem -Path (Join-Path $env:CIPPRootPath 'Modules') -Directory -ErrorAction SilentlyContinue }
        foreach ($ModuleDir in $ModuleDirs) {
            if ($ModuleDir.Name -eq $MyInvocation.MyCommand.ModuleName) { continue }
            $Manifest = Join-Path $ModuleDir.FullName "$($ModuleDir.Name).psd1"
            if (-not (Test-Path -Path $Manifest)) { continue }
            try {
                $Exports = @((Import-PowerShellDataFile -Path $Manifest).FunctionsToExport)
            } catch {
                continue
            }
            # Source checkouts keep the '*' wildcard; built manifests list every export.
            if ($Exports -contains '*') {
                $Exports = @((Get-ChildItem -Path (Join-Path $ModuleDir.FullName 'Public') -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue).BaseName)
            }
            foreach ($Export in $Exports) {
                if ($Export -and -not $Index.ContainsKey($Export)) {
                    $Index[$Export] = [System.Tuple]::Create([string]$Export, $ModuleDir.Name)
                }
            }
        }
        $script:CIPPCommandIndex = $Index
    }

    $Resolved = $null
    if ($script:CIPPCommandIndex.TryGetValue($Name, [ref]$Resolved)) {
        [pscustomobject]@{ Name = $Resolved.Item1; ModuleName = $Resolved.Item2 }
    }
}
