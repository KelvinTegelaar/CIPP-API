function Assert-CippVersion {
    <#
    .SYNOPSIS
    Compare the local version of CIPP with the latest version.

    .DESCRIPTION
    Retrieves the local version of CIPP and compares it with the latest version in GitHub.

    .PARAMETER CIPPVersion
    Local version of CIPP frontend

    #>
    Param($CIPPVersion)
    $APIVersion = (Get-Content 'version_latest.txt' -Raw).trim()

    $RemoteAPIVersion = (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/KelvinTegelaar/CIPP-API/master/version_latest.txt').trim()
    $RemoteCIPPVersion = (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/KelvinTegelaar/CIPP/main/public/version_latest.txt').trim()


    [PSCustomObject]@{
        LocalCIPPVersion     = $CIPPVersion
        RemoteCIPPVersion    = $RemoteCIPPVersion
        LocalCIPPAPIVersion  = $APIVersion
        RemoteCIPPAPIVersion = $RemoteAPIVersion
        OutOfDateCIPP        = ([semver]$RemoteCIPPVersion -gt [semver]$CIPPVersion)
        OutOfDateCIPPAPI     = ([semver]$RemoteAPIVersion -gt [semver]$APIVersion)
    }
}
