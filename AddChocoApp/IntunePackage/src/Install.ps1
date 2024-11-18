[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $PackageName,

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
    if ($Trace) { Start-Transcript -Path (Join-Path $env:windir "\temp\choco-$PackageName-trace.log") }
    $chocoPath = "$($ENV:SystemDrive)\ProgramData\chocolatey\bin\choco.exe"

    if ($InstallChoco) {
        if (-not (Test-Path $chocoPath)) {
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                $chocoPath = "$($ENV:SystemDrive)\ProgramData\chocolatey\bin\choco.exe"
            } catch {
                Write-Host "InstallChoco Error: $($_.Exception.Message)"
            }
        }
    }

    try {
        $localPrograms = & "$chocoPath" list --localOnly
        $customRepoString = if ($CustomRepo) { "--source=$CustomRepo" } else { $null }
        if ($localPrograms -like "*$PackageName*" ) {
            Write-Host "Upgrading $PackageName"
            & "$chocoPath" upgrade $PackageName $CustomRepoString
        } else {
            Write-Host "Installing $PackageName"
            & "$chocoPath" install $PackageName -y $CustomRepoString
        }
        Write-Host 'Completed.'
    } catch {
        Write-Host "Install/upgrade error: $($_.Exception.Message)"
    }

} catch {
    Write-Host "Error encountered: $($_.Exception.Message)"
} finally {
    if ($Trace) { Stop-Transcript }
}

exit $?
