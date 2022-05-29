[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $Packagename,

    [Parameter()]
    [switch]
    $InstallChoco,

    [Parameter()]
    [string]
    $CustomRepo
)

$chocoPath = "$($ENV:SystemDrive)\ProgramData\chocolatey\bin\choco.exe"

if ($InstallChoco) {
    if (-not (Test-Path $chocoPath)) {
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    }
}
$localprograms = & $chocoPath list --localonly
$CustomRepoString = if ($CustomRepo) { "-s `"$customrepo`"" } else { $null }
if ($localprograms -like "*$Packagename*" ) {
    & $Chocopath upgrade $Packagename $CustomRepoString
}
else {
    & $Chocopath install $Packagename -y $CustomRepoString
}

return $?
