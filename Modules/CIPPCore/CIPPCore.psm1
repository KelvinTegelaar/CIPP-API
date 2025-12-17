# ModuleBuilder will concatenate all function files into this module
# This block is only used when running from source (not built)
if (Test-Path (Join-Path $PSScriptRoot 'Public')) {
    $Public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public\*.ps1') -Recurse -ErrorAction SilentlyContinue)
    $Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private\*.ps1') -Recurse -ErrorAction SilentlyContinue)
    $Functions = $Public + $Private
    foreach ($import in @($Functions)) {
        try {
            . $import.FullName
        } catch {
            Write-Error -Message "Failed to import function $($import.FullName): $_"
        }
    }

    Export-ModuleMember -Function $Public.BaseName
}
