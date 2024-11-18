[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $PackageName
)
$chocoPath = "$($ENV:SystemDrive)\ProgramData\chocolatey\bin\choco.exe"
& $chocoPath uninstall $PackageName -y
