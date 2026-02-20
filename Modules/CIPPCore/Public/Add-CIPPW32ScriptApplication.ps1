function Add-CIPPW32ScriptApplication {
    <#
    .SYNOPSIS
        Adds a Win32 app with PowerShell script installer to Intune.

    .DESCRIPTION
        Creates a Win32 app using the PowerShell script installer feature.
        Uploads an intunewin file and PowerShell scripts via the scripts endpoint.

    .PARAMETER TenantFilter
        Tenant ID or domain name for the Graph API call.

    .PARAMETER Properties
        PSCustomObject containing all Win32 app properties:
        - displayName (required): Display name of the app
        - description: Description of the app
        - publisher: Publisher name
        - installScript (required): PowerShell install script content (plaintext)
        - uninstallScript: PowerShell uninstall script content (plaintext)
        - detectionScript: PowerShell detection script content (plaintext)
        - runAsAccount: 'system' or 'user' (default: 'system')
        - deviceRestartBehavior: 'allow', 'suppress', or 'force' (default: 'suppress')
        - runAs32Bit: Boolean, run scripts as 32-bit on 64-bit clients (default: false)
        - enforceSignatureCheck: Boolean, enforce script signature validation (default: false)

    .PARAMETER FilePath
        Path to the intunewin file.

    .PARAMETER FileName
        Name of the file from XML metadata.

    .PARAMETER UnencryptedSize
        Unencrypted size of the file from XML metadata.

    .PARAMETER EncryptionInfo
        Hashtable containing encryption information from XML.

    .EXAMPLE
        $Properties = @{
            displayName = 'My Script App'
            installScript = 'Write-Host "Installing..."'
        }
        $EncryptionInfo = @{ EncryptionKey = '...'; MacKey = '...'; ... }
        Add-CIPPW32ScriptApplication -TenantFilter 'contoso.com' -Properties $Properties -FilePath 'app.intunewin' -FileName 'app.intunewin' -UnencryptedSize 1024000 -EncryptionInfo $EncryptionInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Properties,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [int64]$UnencryptedSize,

        [Parameter(Mandatory = $true)]
        [hashtable]$EncryptionInfo
    )

    # Build Win32 app body
    $intuneBody = @{
        '@odata.type'                    = '#microsoft.graph.win32LobApp'
        displayName                      = $Properties.displayName
        description                      = $Properties.description
        publisher                        = $Properties.publisher
        fileName                         = $FileName
        setupFilePath                    = 'N/A'
        minimumSupportedWindowsRelease   = '1607'
        returnCodes                      = @(
            @{ returnCode = 0; type = 'success' }
            @{ returnCode = 1707; type = 'success' }
            @{ returnCode = 3010; type = 'softReboot' }
            @{ returnCode = 1641; type = 'hardReboot' }
            @{ returnCode = 1618; type = 'retry' }
        )
    }

    # Add install experience
    $intuneBody.installExperience = @{
        '@odata.type'         = 'microsoft.graph.win32LobAppInstallExperience'
        runAsAccount          = if ($Properties.runAsAccount) { $Properties.runAsAccount } else { 'system' }
        deviceRestartBehavior = if ($Properties.deviceRestartBehavior) { $Properties.deviceRestartBehavior } else { 'suppress' }
        maxRunTimeInMinutes   = 60
    }

    # Create the app
    $Baseuri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
    $NewApp = New-GraphPostRequest -Uri $Baseuri -Body ($intuneBody | ConvertTo-Json -Depth 10) -Type POST -tenantid $TenantFilter
    Start-Sleep -Milliseconds 200

    # Upload intunewin file using shared helper
    Add-CIPPWin32LobAppContent -AppId $NewApp.id -FilePath $FilePath -FileName $FileName -UnencryptedSize $UnencryptedSize -EncryptionInfo $EncryptionInfo -TenantFilter $TenantFilter

    # Upload PowerShell scripts via the scripts endpoint
    $RunAs32Bit = if ($null -ne $Properties.runAs32Bit) { [bool]$Properties.runAs32Bit } else { $false }
    $EnforceSignatureCheck = if ($null -ne $Properties.enforceSignatureCheck) { [bool]$Properties.enforceSignatureCheck } else { $false }

    $InstallScriptId = $null
    $UninstallScriptId = $null

    if ($Properties.installScript) {
        $InstallScriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Properties.installScript))
        $InstallScriptBody = @{
            '@odata.type'         = '#microsoft.graph.win32LobAppInstallPowerShellScript'
            displayName           = 'install.ps1'
            enforceSignatureCheck = $EnforceSignatureCheck
            runAs32Bit            = $RunAs32Bit
            content               = $InstallScriptContent
        } | ConvertTo-Json

        $InstallScriptResponse = New-GraphPostRequest -Uri "$Baseuri/$($NewApp.id)/microsoft.graph.win32LobApp/contentVersions/1/scripts" -Body $InstallScriptBody -Type POST -tenantid $TenantFilter
        $InstallScriptId = $InstallScriptResponse.id

        # Wait for script to be committed
        do {
            $ScriptState = New-GraphGetRequest -Uri "$Baseuri/$($NewApp.id)/microsoft.graph.win32LobApp/contentVersions/1/scripts/$InstallScriptId" -tenantid $TenantFilter
            if ($ScriptState.state -like '*fail*') {
                throw "Failed to commit install script: $($ScriptState.state)"
            }
            Start-Sleep -Milliseconds 300
        } while ($ScriptState.state -eq 'commitPending')
    }

    if ($Properties.uninstallScript) {
        $UninstallScriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Properties.uninstallScript))
        $UninstallScriptBody = @{
            '@odata.type'         = '#microsoft.graph.win32LobAppUninstallPowerShellScript'
            displayName           = 'uninstall.ps1'
            enforceSignatureCheck = $EnforceSignatureCheck
            runAs32Bit            = $RunAs32Bit
            content               = $UninstallScriptContent
        } | ConvertTo-Json

        $UninstallScriptResponse = New-GraphPostRequest -Uri "$Baseuri/$($NewApp.id)/microsoft.graph.win32LobApp/contentVersions/1/scripts" -Body $UninstallScriptBody -Type POST -tenantid $TenantFilter
        $UninstallScriptId = $UninstallScriptResponse.id

        # Wait for script to be committed
        do {
            $ScriptState = New-GraphGetRequest -Uri "$Baseuri/$($NewApp.id)/microsoft.graph.win32LobApp/contentVersions/1/scripts/$UninstallScriptId" -tenantid $TenantFilter
            if ($ScriptState.state -like '*fail*') {
                throw "Failed to commit uninstall script: $($ScriptState.state)"
            }
            Start-Sleep -Milliseconds 300
        } while ($ScriptState.state -eq 'commitPending')
    }

    # Build final commit body with active script references
    $CommitBody = @{
        '@odata.type'             = '#microsoft.graph.win32LobApp'
        committedContentVersion   = '1'
    }

    if ($InstallScriptId) {
        $CommitBody['activeInstallScript'] = @{ targetId = $InstallScriptId }
    }

    if ($UninstallScriptId) {
        $CommitBody['activeUninstallScript'] = @{ targetId = $UninstallScriptId }
    }

    # Add detection rules if provided
    if ($Properties.detectionScript) {
        $DetectionScriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Properties.detectionScript))
        $CommitBody['detectionRules'] = @(
            @{
                '@odata.type'         = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
                scriptContent         = $DetectionScriptContent
                enforceSignatureCheck = $EnforceSignatureCheck
                runAs32Bit            = $RunAs32Bit
            }
        )
    }

    # Commit the app with script references
    $null = New-GraphPostRequest -Uri "$Baseuri/$($NewApp.id)" -tenantid $TenantFilter -Body ($CommitBody | ConvertTo-Json -Depth 10) -Type PATCH

    return $NewApp

}
