[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $Packagename
)
$chocoPath = "$($ENV:SystemDrive)\ProgramData\chocolatey\bin\choco.exe"
& $Chocopath uninstall $Packagename -y

