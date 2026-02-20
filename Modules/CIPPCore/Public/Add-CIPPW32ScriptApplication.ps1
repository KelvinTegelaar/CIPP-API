function Add-CIPPW32ScriptApplication {
    <#
    .SYNOPSIS
        Adds a Win32 app with PowerShell script installer to Intune using the standard Chocolatey package.

    .DESCRIPTION
        Creates a Win32 app that uses the standard Chocolatey intunewin package but with custom PowerShell scripts.
        Always uploads the same Choco package, but uses user-provided scripts for install/uninstall commands.

    .PARAMETER TenantFilter
        Tenant ID or domain name for the Graph API call.

    .PARAMETER Properties
        PSCustomObject containing all Win32 app properties:
        - displayName (required): Display name of the app
        - description: Description of the app
        - publisher: Publisher name
        - installScript (required): PowerShell install script content (plaintext)
        - uninstallScript: PowerShell uninstall script content (plaintext)
        - detectionPath (required): Full path to the file or folder to detect (e.g., 'C:\\Program Files\\MyApp')
        - detectionFile: File name to detect (optional, for folder path detection)
        - detectionType: 'exists', 'modifiedDate', 'createdDate', 'version', 'sizeInMB' (default: 'exists')
        - check32BitOn64System: Boolean, check 32-bit registry/paths on 64-bit systems (default: false)
        - runAsAccount: 'system' or 'user' (default: 'system')
        - deviceRestartBehavior: 'allow', 'suppress', or 'force' (default: 'suppress')

    .EXAMPLE
        $Properties = @{
            displayName = 'My Script App'
            installScript = 'Write-Host "Installing..."'
            detectionPath = 'C:\\Program Files\\MyApp'
            detectionFile = 'app.exe'
        }
        Add-CIPPW32ScriptApplication -TenantFilter 'contoso.com' -Properties $Properties
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Properties
    )

    # Get the standard Chocolatey package location (relative to function app root)
    $IntuneWinFile = 'AddChocoApp\IntunePackage.intunewin'
    $ChocoXmlFile = 'AddChocoApp\Choco.App.xml'

    if (-not (Test-Path $IntuneWinFile)) {
        throw "Chocolatey IntunePackage.intunewin not found at: $IntuneWinFile (Current directory: $PWD)"
    }

    if (-not (Test-Path $ChocoXmlFile)) {
        throw "Choco.App.xml not found at: $ChocoXmlFile (Current directory: $PWD)"
    }

    # Parse the Choco XML to get encryption info. We need a wrapper around the application and this is a tiny intune file, perfect for our purpose.
    [xml]$ChocoXml = Get-Content $ChocoXmlFile
    $EncryptionInfo = @{
        EncryptionKey        = $ChocoXml.ApplicationInfo.EncryptionInfo.EncryptionKey
        MacKey               = $ChocoXml.ApplicationInfo.EncryptionInfo.MacKey
        InitializationVector = $ChocoXml.ApplicationInfo.EncryptionInfo.InitializationVector
        Mac                  = $ChocoXml.ApplicationInfo.EncryptionInfo.Mac
        ProfileIdentifier    = $ChocoXml.ApplicationInfo.EncryptionInfo.ProfileIdentifier
        FileDigest           = $ChocoXml.ApplicationInfo.EncryptionInfo.FileDigest
        FileDigestAlgorithm  = $ChocoXml.ApplicationInfo.EncryptionInfo.FileDigestAlgorithm
    }

    $FileName = $ChocoXml.ApplicationInfo.FileName
    $UnencryptedSize = [int64]$ChocoXml.ApplicationInfo.UnencryptedContentSize

    # Build detection rules
    if ($Properties.detectionPath) {
        # Determine if this is a file or folder detection
        $DetectionRule = @{
            '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemDetection'
            check32BitOn64System = if ($null -ne $Properties.check32BitOn64System) { [bool]$Properties.check32BitOn64System } else { $false }
            detectionType        = if ($Properties.detectionType) { $Properties.detectionType } else { 'exists' }
        }

        if ($Properties.detectionFile) {
            # File detection (path + file)
            $DetectionRule['path'] = $Properties.detectionPath
            $DetectionRule['fileOrFolderName'] = $Properties.detectionFile
        } else {
            # Folder/File detection (full path)
            # Split the path into directory and file/folder name
            $PathItem = Split-Path $Properties.detectionPath -Leaf
            $ParentPath = Split-Path $Properties.detectionPath -Parent

            if ([string]::IsNullOrEmpty($ParentPath)) {
                throw "Invalid detection path: $($Properties.detectionPath). Must be a full path."
            }

            $DetectionRule['path'] = $ParentPath
            $DetectionRule['fileOrFolderName'] = $PathItem
        }

        $DetectionRules = @($DetectionRule)
    } else {
        # Default detection: Check for a marker file in ProgramData
        $DetectionRules = @(
            @{
                '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemDetection'
                path                 = '%ProgramData%\CIPPApps'
                fileOrFolderName     = "$($Properties.displayName -replace '[^a-zA-Z0-9]', '_').txt"
                check32BitOn64System = $false
                detectionType        = 'exists'
            }
        )
    }

    # Build the Win32 app body
    $AppBody = @{
        '@odata.type'                  = '#microsoft.graph.win32LobApp'
        displayName                    = $Properties.displayName
        description                    = $Properties.description
        publisher                      = if ($Properties.publisher) { $Properties.publisher } else { 'CIPP' }
        fileName                       = $FileName
        setupFilePath                  = 'N/A'
        installCommandLine             = 'powershell.exe -ExecutionPolicy Bypass -File install.ps1'
        uninstallCommandLine           = 'powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1'
        minimumSupportedWindowsRelease = '1607'
        detectionRules                 = $DetectionRules
        returnCodes                    = @(
            @{ returnCode = 0; type = 'success' }
            @{ returnCode = 1707; type = 'success' }
            @{ returnCode = 3010; type = 'softReboot' }
            @{ returnCode = 1641; type = 'hardReboot' }
            @{ returnCode = 1618; type = 'retry' }
        )
        installExperience              = @{
            '@odata.type'         = 'microsoft.graph.win32LobAppInstallExperience'
            runAsAccount          = if ($Properties.runAsAccount) { $Properties.runAsAccount } else { 'system' }
            deviceRestartBehavior = if ($Properties.deviceRestartBehavior) { $Properties.deviceRestartBehavior } else { 'suppress' }
        }
    }

    # Create the app first
    $Baseuri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
    $NewApp = New-GraphPostRequest -Uri $Baseuri -Body ($AppBody | ConvertTo-Json -Depth 10) -Type POST -tenantid $TenantFilter
    Start-Sleep -Milliseconds 200

    # Upload the Chocolatey intunewin content
    Add-CIPPWin32LobAppContent -AppId $NewApp.id -FilePath $IntuneWinFile -FileName $FileName -UnencryptedSize $UnencryptedSize -EncryptionInfo $EncryptionInfo -TenantFilter $TenantFilter

    # Upload PowerShell scripts via the scripts endpoint (newer method)
    $InstallScriptId = $null
    $UninstallScriptId = $null

    if ($Properties.installScript) {
        $InstallScriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Properties.installScript))
        $InstallScriptBody = @{
            '@odata.type'         = '#microsoft.graph.win32LobAppInstallPowerShellScript'
            displayName           = 'install.ps1'
            enforceSignatureCheck = $false
            runAs32Bit            = $false
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
            enforceSignatureCheck = $false
            runAs32Bit            = $false
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
        '@odata.type'           = '#microsoft.graph.win32LobApp'
        committedContentVersion = '1'
    }

    if ($InstallScriptId) {
        $CommitBody['activeInstallScript'] = @{ targetId = $InstallScriptId }
    }

    if ($UninstallScriptId) {
        $CommitBody['activeUninstallScript'] = @{ targetId = $UninstallScriptId }
    }

    # Commit the app with script references
    $null = New-GraphPostRequest -Uri "$Baseuri/$($NewApp.id)" -tenantid $TenantFilter -Body ($CommitBody | ConvertTo-Json -Depth 10) -Type PATCH

    return $NewApp
}
