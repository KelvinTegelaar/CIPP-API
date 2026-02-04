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
    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $APIVersion = (Get-Content -Path $CIPPRoot\version_latest.txt).trim()

    $RemoteAPIVersion = (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/KelvinTegelaar/CIPP-API/master/version_latest.txt').trim()
    $RemoteCIPPVersion = (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/KelvinTegelaar/CIPP/main/public/version.json').version

    [PSCustomObject]@{
        LocalCIPPVersion     = $CIPPVersion
        RemoteCIPPVersion    = $RemoteCIPPVersion
        LocalCIPPAPIVersion  = $APIVersion
        RemoteCIPPAPIVersion = $RemoteAPIVersion
        OutOfDateCIPP        = ([semver]$RemoteCIPPVersion -gt [semver]$CIPPVersion)
        OutOfDateCIPPAPI     = ([semver]$RemoteAPIVersion -gt [semver]$APIVersion)
    }
}
