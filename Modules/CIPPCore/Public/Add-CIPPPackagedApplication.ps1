function Add-CIPPPackagedApplication {
    <#
    .SYNOPSIS
        Adds a packaged Win32Lob application to Intune.

    .DESCRIPTION
        Handles creation of Win32Lob apps with intunewin files and uploads the content.

    .PARAMETER AppBody
        Hashtable or PSCustomObject containing the app configuration.

    .PARAMETER TenantFilter
        Tenant ID or domain name for the Graph API call.

    .PARAMETER AppType
        Type of app: 'Choco' or 'MSPApp'.

    .PARAMETER FilePath
        Path to the intunewin file.

    .PARAMETER FileName
        Name of the file from XML metadata.

    .PARAMETER UnencryptedSize
        Unencrypted size of the file from XML metadata.

    .PARAMETER EncryptionInfo
        Hashtable containing encryption information from XML.

    .PARAMETER DisplayName
        Display name of the app for logging.

    .PARAMETER APIName
        API name for logging (optional).

    .PARAMETER Headers
        Request headers for logging (optional).

    .EXAMPLE
        $AppBody = @{ '@odata.type' = '#microsoft.graph.win32LobApp'; displayName = 'My App' }
        $EncryptionInfo = @{ EncryptionKey = '...'; MacKey = '...'; ... }
        Add-CIPPPackagedApplication -AppBody $AppBody -TenantFilter 'contoso.com' -AppType 'Choco' -FilePath 'app.intunewin' -FileName 'app.intunewin' -UnencryptedSize 1024000 -EncryptionInfo $EncryptionInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$AppBody,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [int64]$UnencryptedSize,

        [Parameter(Mandatory = $true)]
        [hashtable]$EncryptionInfo,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName
    )

    $BaseUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'

    # Create the Win32Lob app
    $NewApp = New-GraphPostRequest -Uri $BaseUri -Body ($AppBody | ConvertTo-Json) -Type POST -tenantid $TenantFilter

    # Upload intunewin content
    Add-CIPPWin32LobAppContent -AppId $NewApp.id -FilePath $FilePath -FileName $FileName -UnencryptedSize $UnencryptedSize -EncryptionInfo $EncryptionInfo -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers

    return $NewApp
}
