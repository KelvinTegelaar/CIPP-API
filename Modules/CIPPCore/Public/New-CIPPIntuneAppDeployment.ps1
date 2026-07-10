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
        $PackageName = [string]$AppConfig.PackageName
        if ([string]::IsNullOrWhiteSpace($PackageName)) {
            throw 'PackageName is required for Choco app deployments.'
        }

        if (-not [regex]::IsMatch($PackageName, '^[A-Za-z0-9][A-Za-z0-9._-]*$')) {
            throw "Invalid PackageName '$PackageName'. Allowed characters: letters, numbers, dot, underscore, hyphen."
        }

        $IntuneBody = Get-Content (Join-Path $env:CIPPRootPath 'AddChocoApp\Choco.app.json') | ConvertFrom-Json
        $IntuneBody.description = $AppConfig.description
        $IntuneBody.displayName = $AppConfig.ApplicationName
        $IntuneBody.installExperience.runAsAccount = if ($AppConfig.InstallAsSystem) { 'system' } else { 'user' }
        $IntuneBody.installExperience.deviceRestartBehavior = if ($AppConfig.DisableRestart) { 'suppress' } else { 'allow' }
        $PackageNameArg = ConvertTo-CIPPSafePwshArg -Value $PackageName
        $IntuneBody.installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\Install.ps1 -InstallChoco -Packagename $PackageNameArg"
        if ($AppConfig.customrepo) {
            $CustomRepoArg = ConvertTo-CIPPSafePwshArg -Value ([string]$AppConfig.CustomRepo)
            $IntuneBody.installCommandLine = $IntuneBody.installCommandLine + " -CustomRepo $CustomRepoArg"
        }
        if ($AppConfig.customArguments) {
            $CustomArgumentsArg = ConvertTo-CIPPSafePwshArg -Value ([string]$AppConfig.customArguments)
            $IntuneBody.installCommandLine = $IntuneBody.installCommandLine + " -CustomArguments $CustomArgumentsArg"
        }
        $IntuneBody.UninstallCommandLine = "powershell.exe -ExecutionPolicy Bypass .\Uninstall.ps1 -Packagename $PackageNameArg"
        $IntuneBody.detectionRules[0].path = "$($ENV:SystemDrive)\programdata\chocolatey\lib"
        $IntuneBody.detectionRules[0].fileOrFolderName = $PackageName

        if ($IntuneBody.installCommandLine -match '%') {
            $IntuneBody.installCommandLine = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $IntuneBody.installCommandLine
        }
    }

    # Build IntuneBody from raw config if not pre-built (template/standard path). MSP apps store
    # only the vendor + params in the template, so build the install command here using the shared
    # helper, which resolves %CIPP variables% in the params per-tenant.
    if (-not $IntuneBody -and $AppType -eq 'MSPApp') {
        $MSPAppName = $AppConfig.MSPAppName ?? $AppConfig.rmmname.value ?? $AppConfig.rmmname
        if ([string]::IsNullOrWhiteSpace($MSPAppName)) {
            throw 'MSP app vendor (rmmname) is required for MSP app deployments but was not found in the template config.'
        }
        # Ensure the file-loading block below can locate the packaged app files.
        $AppConfig | Add-Member -NotePropertyName 'MSPAppName' -NotePropertyValue $MSPAppName -Force

        $IntuneBody = Get-Content (Join-Path $env:CIPPRootPath "AddMSPApp\$MSPAppName.app.json") | ConvertFrom-Json
        $IntuneBody.displayName = $AppConfig.Applicationname ?? $AppConfig.displayName

        $TenantObj = Get-Tenants -TenantFilter $TenantFilter
        $CommandResult = Get-CIPPMSPAppInstallCommand -RmmName $MSPAppName -Params $AppConfig.params -Tenant $TenantObj -PackageName $AppConfig.PackageName
        $IntuneBody.installCommandLine = $CommandResult.InstallCommandLine
        $IntuneBody.UninstallCommandLine = $CommandResult.UninstallCommandLine
        if ($CommandResult.DetectionScriptContent) {
            $IntuneBody.detectionRules[0].scriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CommandResult.DetectionScriptContent))
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
