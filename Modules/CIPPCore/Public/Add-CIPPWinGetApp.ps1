function Add-CIPPWinGetApp {
    <#
    .SYNOPSIS
        Creates a WinGet app in Intune.

    .DESCRIPTION
        Creates a new WinGet app using the provided app body.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$AppBody,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $BaseUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'

    # Create the WinGet app
    $NewApp = New-GraphPostRequest -Uri $BaseUri -Body ($AppBody | ConvertTo-Json -Compress) -Type POST -tenantid $TenantFilter

    return $NewApp
}
