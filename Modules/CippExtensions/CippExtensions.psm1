$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -ErrorAction SilentlyContinue)
$NinjaOne = @(Get-ChildItem -Path $PSScriptRoot\NinjaOne\*.ps1 -ErrorAction SilentlyContinue)
$Functions = $Public + $Private + $NinjaOne
foreach ($import in @($Functions)) {
    try {
        . $import.FullName
    } catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

Export-ModuleMember -Function $Functions.BaseName -Alias *
