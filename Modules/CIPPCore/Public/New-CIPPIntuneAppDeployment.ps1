function New-CIPPIntuneAppDeployment {
    <#
    .SYNOPSIS
        Deploys a single Intune application to a tenant.
    .DESCRIPTION
        Shared deployment function used by both Push-UploadApplication (queue processing)
        and standards. Handles app existence check, type routing, and assignment.
        Accepts either a pre-built AppConfig (with IntuneBody, from queue) or raw template
        config (appType + raw fields) and builds the deployment config internally.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AppConfig,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$APIName = 'AppUpload'
    )

    $IntuneBody = $AppConfig.IntuneBody
    $AssignTo = $AppConfig.assignTo
    $AssignToIntent = $AppConfig.InstallationIntent
    $ExcludeGroup = $AppConfig.excludeGroup
    $AppType = if ($AppConfig.type) { $AppConfig.type } else { 'Choco' }

    # Build IntuneBody from raw config if not pre-built (template/standard path)
    if (-not $IntuneBody -and $AppType -eq 'WinGet') {
        $PackageId = $AppConfig.packagename ?? $AppConfig.PackageName
        $AppDisplayName = $AppConfig.applicationName ?? $AppConfig.ApplicationName
        if (-not $PackageId) {
            throw "PackageName/packagename is required for WinGet apps but was not found in the config for '$AppDisplayName'."
        }
        $IntuneBody = [ordered]@{
            '@odata.type'       = '#microsoft.graph.winGetApp'
            'displayName'       = "$AppDisplayName"
            'description'       = "$($AppConfig.description)"
            'packageIdentifier' = "$PackageId"
            'installExperience' = @{
                '@odata.type'  = 'microsoft.graph.winGetAppInstallExperience'
                'runAsAccount' = 'system'
            }
        }
    }

    if (-not $IntuneBody -and $AppType -eq 'Choco') {
        $IntuneBody = Get-Content (Join-Path $env:CIPPRootPath 'AddChocoApp\Choco.app.json') | ConvertFrom-Json
        $IntuneBody.description = $AppConfig.description
        $IntuneBody.displayName = $AppConfig.ApplicationName
        $IntuneBody.installExperience.runAsAccount = if ($AppConfig.InstallAsSystem) { 'system' } else { 'user' }
        $IntuneBody.installExperience.deviceRestartBehavior = if ($AppConfig.DisableRestart) { 'suppress' } else { 'allow' }
        $IntuneBody.installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\Install.ps1 -InstallChoco -Packagename $($AppConfig.PackageName)"
        if ($AppConfig.customrepo) {
            $IntuneBody.installCommandLine = $IntuneBody.installCommandLine + " -CustomRepo $($AppConfig.CustomRepo)"
        }
        if ($AppConfig.customArguments) {
            $IntuneBody.installCommandLine = $IntuneBody.installCommandLine + " -CustomArguments '$($AppConfig.customArguments)'"
        }
        $IntuneBody.UninstallCommandLine = "powershell.exe -ExecutionPolicy Bypass .\Uninstall.ps1 -Packagename $($AppConfig.PackageName)"
        $IntuneBody.detectionRules[0].path = "$($ENV:SystemDrive)\programdata\chocolatey\lib"
        $IntuneBody.detectionRules[0].fileOrFolderName = "$($AppConfig.PackageName)"

        if ($IntuneBody.installCommandLine -match '%') {
            $IntuneBody.installCommandLine = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $IntuneBody.installCommandLine
        }
    }

    # Load files based on app type (only for types that need them)
    $Intunexml = $null
    $Infile = $null
    if ($AppType -eq 'MSPApp') {
        [xml]$Intunexml = Get-Content (Join-Path $env:CIPPRootPath "AddMSPApp\$($AppConfig.MSPAppName).app.xml")
        $Infile = Join-Path $env:CIPPRootPath "AddMSPApp\$($AppConfig.MSPAppName).intunewin"
    } elseif ($AppType -in @('Choco', 'Win32ScriptApp')) {
        [xml]$Intunexml = Get-Content (Join-Path $env:CIPPRootPath 'AddChocoApp\Choco.App.xml')
        $Infile = Join-Path $env:CIPPRootPath "AddChocoApp\$($Intunexml.ApplicationInfo.FileName)"
    }

    $BaseUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'

    # Check if app already exists (any type with matching display name)
    $ApplicationList = New-GraphGetRequest -Uri $BaseUri -tenantid $TenantFilter | Where-Object { $_.DisplayName -eq $AppConfig.Applicationname }
    if ($ApplicationList.displayname.count -ge 1) {
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "$($AppConfig.Applicationname) exists. Skipping this application" -Sev 'Info'
        return $null
    }

    # Route to appropriate handler based on app type
    $NewApp = $null
    switch ($AppType) {
        'WinGet' {
            $NewApp = Add-CIPPWinGetApp -AppBody $IntuneBody -TenantFilter $TenantFilter
        }
        'Choco' {
            $EncryptionInfo = @{
                EncryptionKey        = $Intunexml.ApplicationInfo.EncryptionInfo.EncryptionKey
                MacKey               = $Intunexml.ApplicationInfo.EncryptionInfo.MacKey
                InitializationVector = $Intunexml.ApplicationInfo.EncryptionInfo.InitializationVector
                Mac                  = $Intunexml.ApplicationInfo.EncryptionInfo.Mac
                ProfileIdentifier    = $Intunexml.ApplicationInfo.EncryptionInfo.ProfileIdentifier
                FileDigest           = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigest
                FileDigestAlgorithm  = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigestAlgorithm
            }

            $Params = @{
                AppBody         = $IntuneBody
                TenantFilter    = $TenantFilter
                FilePath        = $Infile
                FileName        = $Intunexml.ApplicationInfo.FileName
                UnencryptedSize = [int64]$Intunexml.ApplicationInfo.UnencryptedContentSize
                EncryptionInfo  = $EncryptionInfo
            }
            if ($AppConfig.Applicationname) { $Params.DisplayName = $AppConfig.Applicationname }

            $NewApp = Add-CIPPPackagedApplication @Params
        }
        'MSPApp' {
            $EncryptionInfo = @{
                EncryptionKey        = $Intunexml.ApplicationInfo.EncryptionInfo.EncryptionKey
                MacKey               = $Intunexml.ApplicationInfo.EncryptionInfo.MacKey
                InitializationVector = $Intunexml.ApplicationInfo.EncryptionInfo.InitializationVector
                Mac                  = $Intunexml.ApplicationInfo.EncryptionInfo.Mac
                ProfileIdentifier    = $Intunexml.ApplicationInfo.EncryptionInfo.ProfileIdentifier
                FileDigest           = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigest
                FileDigestAlgorithm  = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigestAlgorithm
            }

            $Params = @{
                AppBody         = $IntuneBody
                TenantFilter    = $TenantFilter
                FilePath        = $Infile
                FileName        = $Intunexml.ApplicationInfo.FileName
                UnencryptedSize = [int64]$Intunexml.ApplicationInfo.UnencryptedContentSize
                EncryptionInfo  = $EncryptionInfo
            }
            if ($AppConfig.Applicationname) { $Params.DisplayName = $AppConfig.Applicationname }

            $NewApp = Add-CIPPPackagedApplication @Params
        }
        'Win32ScriptApp' {
            $Properties = @{
                displayName   = $AppConfig.Applicationname
                installScript = $AppConfig.installScript
            }

            if ($AppConfig.description) { $Properties['description'] = $AppConfig.description }
            if ($AppConfig.publisher) { $Properties['publisher'] = $AppConfig.publisher }
            if ($AppConfig.uninstallScript) { $Properties['uninstallScript'] = $AppConfig.uninstallScript }
            if ($AppConfig.detectionScript) { $Properties['detectionScript'] = $AppConfig.detectionScript }
            if ($AppConfig.detectionPath) { $Properties['detectionPath'] = $AppConfig.detectionPath }
            if ($AppConfig.detectionFile) { $Properties['detectionFile'] = $AppConfig.detectionFile }
            if ($AppConfig.runAsAccount) { $Properties['runAsAccount'] = $AppConfig.runAsAccount }
            if ($AppConfig.deviceRestartBehavior) { $Properties['deviceRestartBehavior'] = $AppConfig.deviceRestartBehavior }
            if ($null -ne $AppConfig.runAs32Bit) { $Properties['runAs32Bit'] = $AppConfig.runAs32Bit }
            if ($null -ne $AppConfig.enforceSignatureCheck) { $Properties['enforceSignatureCheck'] = $AppConfig.enforceSignatureCheck }

            $NewApp = Add-CIPPW32ScriptApplication -TenantFilter $TenantFilter -Properties ([PSCustomObject]$Properties)
        }
        'OfficeApp' {
            # Strip read-only properties that Graph API won't accept on create
            $ObjBody = $IntuneBody
            if ($ObjBody -is [string]) { $ObjBody = $ObjBody | ConvertFrom-Json -Depth 100 }
            $ReadOnlyProps = @('id', 'createdDateTime', 'lastModifiedDateTime', 'uploadState', 'publishingState', 'isAssigned', 'roleScopeTagIds', 'dependentAppCount', 'supersedingAppCount', 'supersededAppCount', 'committedContentVersion', 'fileName', 'size', 'assignments@odata.context', 'assignments', 'AppAssignment', 'AppExclude')
            foreach ($prop in $ReadOnlyProps) {
                if ($ObjBody.PSObject.Properties[$prop]) {
                    $ObjBody.PSObject.Properties.Remove($prop)
                }
            }
            $NewApp = New-GraphPostRequest -Uri $BaseUri -tenantid $TenantFilter -Body (ConvertTo-Json -InputObject $ObjBody -Depth 10) -Type POST
        }
        default {
            throw "Unsupported app type: $AppType"
        }
    }

    # Log success and assign app if requested
    if ($NewApp) {
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "$($AppConfig.Applicationname) Successfully created" -Sev 'Info'

        if ($AssignTo -and $AssignTo -ne 'On') {
            $Intent = if ($AssignToIntent) { 'Uninstall' } else { 'Required' }
            $AppTypeForAssignment = switch ($AppType) {
                'WinGet' { 'WinGet' }
                'WinGetNew' { 'WinGet' }
                'OfficeApp' { $null }
                default { 'Win32Lob' }
            }
            Start-Sleep -Milliseconds 200
            $AssignParams = @{
                ApplicationId = $NewApp.Id
                TenantFilter  = $TenantFilter
                GroupName     = $AssignTo
                ExcludeGroup  = $ExcludeGroup
                Intent        = $Intent
                APIName       = $APIName
            }
            if ($AppTypeForAssignment) { $AssignParams.AppType = $AppTypeForAssignment }
            Set-CIPPAssignedApplication @AssignParams
        }
    }

    return $NewApp
}
