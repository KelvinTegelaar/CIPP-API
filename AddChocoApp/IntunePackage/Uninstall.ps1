[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $Packagename
)
$chocoPath = "$($env:SystemDrive)\ProgramData\chocolatey\bin\choco.exe"
& $Chocopath uninstall $Packagename -y

