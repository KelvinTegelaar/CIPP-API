$Functions = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue) + @(Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -ErrorAction SilentlyContinue)
foreach ($import in @($Functions))
{
    try
    {
        . $import.FullName
    }
    catch
    {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}