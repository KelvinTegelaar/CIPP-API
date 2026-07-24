function Assert-CippVersion {
    <#
    .SYNOPSIS
    Compare the local version of CIPP with the latest version.

    .DESCRIPTION
    Retrieves the local version of CIPP and compares it with the latest version in GitHub.

    .PARAMETER CIPPVersion
    Local version of CIPP frontend

    #>
    param($CIPPVersion)

    if ($env:CIPPNG -eq 'true') {
        $APIVersion = $env:APP_VERSION
        if (!$CIPPVersion) {
            $CIPPVersion = $env:APP_VERSION
        }
    } else {
        $APIVersion = (Get-Content -Path (Join-Path $env:CIPPRootPath 'version_latest.txt')).trim()
    }

    $RemoteAPIVersion = (Invoke-CIPPRestMethod -Uri 'https://raw.githubusercontent.com/KelvinTegelaar/CIPP-API/master/version_latest.txt').trim()
    $RemoteCIPPVersion = (Invoke-CIPPRestMethod -Uri 'https://raw.githubusercontent.com/CyberDrain/CIPP/main/backend/version_latest.txt').trim()

    [PSCustomObject]@{
        LocalCIPPVersion     = $CIPPVersion
        RemoteCIPPVersion    = $RemoteCIPPVersion
        LocalCIPPAPIVersion  = $APIVersion
        RemoteCIPPAPIVersion = $RemoteAPIVersion
        OutOfDateCIPP        = ([semver]$RemoteCIPPVersion -gt [semver]$CIPPVersion)
        OutOfDateCIPPAPI     = ([semver]$RemoteAPIVersion -gt [semver]$APIVersion)
    }
}
