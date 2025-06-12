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
    $CustomRepo,

    [Parameter()]
    [switch]
    $Trace
)

try {
    if ($Trace) { Start-Transcript -Path (Join-Path $env:windir "\temp\choco-$Packagename-trace.log") }
    $chocoPath = "$($env:SystemDrive)\ProgramData\chocolatey\bin\choco.exe"

    if ($InstallChoco) {
        if (-not (Test-Path $chocoPath)) {
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                $chocoPath = "$($env:SystemDrive)\ProgramData\chocolatey\bin\choco.exe"
            }
            catch {
                Write-Host "InstallChoco Error: $($_.Exception.Message)"
            }
        }
    }

    try {
        $localprograms = & "$chocoPath" list --localonly
        $CustomRepoString = if ($CustomRepo) { "--source $customrepo" } else { $null }
        if ($localprograms -like "*$Packagename*" ) {
            Write-Host "Upgrading $packagename"
            & "$chocoPath" upgrade $Packagename $CustomRepoString
        }
        else {
            Write-Host "Installing $packagename"
            & "$chocoPath" install $Packagename -y $CustomRepoString
        }
        Write-Host 'Completed.'
    }
    catch {
        Write-Host "Install/upgrade error: $($_.Exception.Message)"
    }

}
catch {
    Write-Host "Error encountered: $($_.Exception.Message)"
}
finally {
    if ($Trace) { Stop-Transcript }
}

exit $?
