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

    # Older templates may hold a Graph-read body (has an id); only Office/Edge can deploy from one.
    $IsScriptApp = $AppType -eq 'Win32ScriptApp' -and $AppConfig.installScript
    if ($IntuneBody.id -and $AppType -notin @('OfficeApp', 'EdgeApp') -and -not $IsScriptApp) {
        throw "'$($AppConfig.Applicationname)' was templated from an existing Intune application with uploaded installer content. CIPP cannot deploy uploaded installer content; only script or package based applications can be templated. Rebuild this template entry as a Store, Chocolatey, Office, Edge, MSP or Custom Application."
    }

    # Build IntuneBody from raw config if not pre-built (template/standard path)
    if (-not $IntuneBody -and $AppType -eq 'WinGet') {
        $PackageId = $AppConfig.packagename ?? $AppConfig.PackageName
        $AppDisplayName = $AppConfig.applicationName ?? $AppConfig.ApplicationName
        if (-not $PackageId) {
            throw "PackageName/packagename is required for WinGet apps but was not found in the config for '$AppDisplayName'."
        }
        # Default to system when InstallAsSystem is absent so existing templates keep their behavior
        $RunAsAccount = if ($null -ne $AppConfig.InstallAsSystem -and -not [bool]$AppConfig.InstallAsSystem) { 'user' } else { 'system' }
        $IntuneBody = [ordered]@{
            '@odata.type'       = '#microsoft.graph.winGetApp'
            'displayName'       = "$AppDisplayName"
            'description'       = "$($AppConfig.description)"
            'packageIdentifier' = "$PackageId"
            'installExperience' = @{
                '@odata.type'  = 'microsoft.graph.winGetAppInstallExperience'
                'runAsAccount' = $RunAsAccount
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

    # Check if app already exists (any type with matching display name). Office and Edge are
    # singletons per tenant whose Graph display name may differ from the template, so match on type.
    $ApplicationList = switch ($AppType) {
        'OfficeApp' { New-GraphGetRequest -Uri $BaseUri -tenantid $TenantFilter | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.officeSuiteApp' } }
        'EdgeApp' { New-GraphGetRequest -Uri $BaseUri -tenantid $TenantFilter | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windowsMicrosoftEdgeApp' } }
        # Uploaded packages decide create/update/supersede themselves below.
        { $_ -in @('Win32PackageApp', 'MacOSPackageApp') } { @() }
        default { New-GraphGetRequest -Uri $BaseUri -tenantid $TenantFilter | Where-Object { $_.DisplayName -eq $AppConfig.Applicationname } }
    }
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
            # Templates built in the wizard carry the individual Office fields rather than a
            # pre-built IntuneBody, so build the body the same way Invoke-AddOfficeApp does.
            $ObjBody = Get-CIPPOfficeAppBody -Config $AppConfig
            if (-not $ObjBody) {
                throw "No Office configuration could be built from the supplied settings for '$($AppConfig.Applicationname)'."
            }
            $NewApp = New-GraphPostRequest -Uri $BaseUri -tenantid $TenantFilter -Body (ConvertTo-Json -InputObject $ObjBody -Depth 10) -Type POST
        }
        'EdgeApp' {
            $ObjBody = Get-CIPPEdgeAppBody -Config $AppConfig
            if (-not $ObjBody) {
                throw "No Edge configuration could be built from the supplied settings for '$($AppConfig.Applicationname)'."
            }
            $NewApp = New-GraphPostRequest -Uri $BaseUri -tenantid $TenantFilter -Body (ConvertTo-Json -InputObject $ObjBody -Depth 10) -Type POST
        }
        { $_ -in @('Win32PackageApp', 'MacOSPackageApp') } {
            $PackageId = [guid]::Empty
            if (-not [guid]::TryParse([string]$AppConfig.packageId, [ref]$PackageId)) { throw "'$($AppConfig.Applicationname)' has no uploaded package." }
            $PackageStorage = (Get-CIPPAppPackageStorage -PackageId "$PackageId").ConnectionString
            $PackageMetadata = New-CIPPAzStorageRequest -Service blob -ConnectionString $PackageStorage -Resource "app-packages/$PackageId/metadata.json" -ErrorAction SilentlyContinue
            if (-not $PackageMetadata.Bytes) { throw "The package for '$($AppConfig.Applicationname)' is no longer in CIPP storage. Upload it again in the application template." }
            $Package = [System.Text.Encoding]::UTF8.GetString($PackageMetadata.Bytes) | ConvertFrom-Json
            $Marker = "Package: $PackageId"

            if ($AppType -eq 'MacOSPackageApp') {
                $LobType = if ($Package.FileName -match '\.dmg$') { 'macOSDmgApp' } else { 'macOSPkgApp' }
                # One app per line: '<bundle id> <version>'
                $IncludedApps = @(([string]$AppConfig.includedApps -split "`n").ForEach({ $_.Trim() }).Where({ $_ }).ForEach({
                            $Parts = $_ -split '\s+', 2
                            @{ '@odata.type' = '#microsoft.graph.macOSIncludedApp'; bundleId = $Parts[0]; bundleVersion = "$($Parts[1])" }
                        }))
                $PrimaryBundleId = $AppConfig.primaryBundleId ?? $IncludedApps[0].bundleId
                $PrimaryBundleVersion = $AppConfig.primaryBundleVersion ?? $IncludedApps[0].bundleVersion
                if (-not $PrimaryBundleId) { throw "'$($AppConfig.Applicationname)' needs the app's bundle ID." }
                if ($IncludedApps.Where({ $_.bundleId -eq $PrimaryBundleId }).Count -eq 0) {
                    $IncludedApps = @(@{ '@odata.type' = '#microsoft.graph.macOSIncludedApp'; bundleId = $PrimaryBundleId; bundleVersion = "$PrimaryBundleVersion" }; $IncludedApps)
                }
                $MinimumOS = $AppConfig.minimumMacOS.value ?? $AppConfig.minimumMacOS ?? 'v12_0'
                $AppBody = [ordered]@{
                    '@odata.type'                   = "#microsoft.graph.$LobType"
                    displayName                     = "$($AppConfig.Applicationname)"
                    description                     = "$($AppConfig.description)"
                    publisher                       = "$($AppConfig.publisher)"
                    notes                           = $Marker
                    fileName                        = $Package.FileName
                    primaryBundleId                 = $PrimaryBundleId
                    primaryBundleVersion            = "$PrimaryBundleVersion"
                    includedApps                    = $IncludedApps
                    ignoreVersionDetection          = [bool]$AppConfig.ignoreVersionDetection
                    minimumSupportedOperatingSystem = @{ '@odata.type' = '#microsoft.graph.macOSMinimumOperatingSystem'; $MinimumOS = $true }
                }
                if ($LobType -eq 'macOSPkgApp') {
                    foreach ($Script in 'preInstallScript', 'postInstallScript') {
                        if ($AppConfig.$Script) { $AppBody[$Script] = @{ '@odata.type' = '#microsoft.graph.macOSAppScript'; scriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$AppConfig.$Script)) } }
                    }
                }
            } else {
                $LobType = 'win32LobApp'
                $Detection = switch ([string]$AppConfig.detectionType) {
                    'msi' {
                        $ProductCode = $AppConfig.msiProductCode ?? $Package.MsiInfo.MsiProductCode
                        @{ '@odata.type' = '#microsoft.graph.win32LobAppProductCodeRule'; ruleType = 'detection'; productCode = $ProductCode
                            productVersionOperator = $AppConfig.msiProductVersion ? 'greaterThanOrEqual' : 'notConfigured'; productVersion = $AppConfig.msiProductVersion
                        }
                    }
                    'registry' {
                        @{ '@odata.type' = '#microsoft.graph.win32LobAppRegistryRule'; ruleType = 'detection'; keyPath = $AppConfig.registryKeyPath; valueName = $AppConfig.registryValueName
                            check32BitOn64System = [bool]$AppConfig.check32BitOn64System; operationType = $AppConfig.registryValue ? 'version' : 'exists'
                            operator = $AppConfig.registryValue ? 'greaterThanOrEqual' : 'notConfigured'; comparisonValue = $AppConfig.registryValue
                        }
                    }
                    'script' {
                        @{ '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptRule'; ruleType = 'detection'; enforceSignatureCheck = [bool]$AppConfig.enforceSignatureCheck
                            runAs32Bit = [bool]$AppConfig.runAs32Bit; operationType = 'notConfigured'; operator = 'notConfigured'
                            scriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$AppConfig.detectionScript))
                        }
                    }
                    default {
                        @{ '@odata.type' = '#microsoft.graph.win32LobAppFileSystemRule'; ruleType = 'detection'; path = $AppConfig.detectionPath; fileOrFolderName = $AppConfig.detectionFile
                            check32BitOn64System = [bool]$AppConfig.check32BitOn64System; operationType = $AppConfig.fileVersion ? 'version' : 'exists'
                            operator = $AppConfig.fileVersion ? 'greaterThanOrEqual' : 'notConfigured'; comparisonValue = $AppConfig.fileVersion
                        }
                    }
                }
                $Architectures = @(@($AppConfig.architectures).ForEach({ "$($_.value ?? $_)" }).Where({ $_ }))
                if ($Architectures.Count -eq 0) { $Architectures = @('x64', 'x86') }
                # 'code=type' pairs, e.g. '0=success, 3010=softReboot'
                $ReturnCodes = @(([string]$AppConfig.returnCodes -split ',').Where({ $_ -match '^\s*(-?\d+)\s*=\s*(success|softReboot|hardReboot|retry|failed)\s*$' }).ForEach({
                            $Pair = $_ -split '='
                            @{ returnCode = [int]$Pair[0].Trim(); type = $Pair[1].Trim() }
                        }))
                if ($ReturnCodes.Count -eq 0) {
                    $ReturnCodes = @(@{ returnCode = 0; type = 'success' }, @{ returnCode = 1707; type = 'success' }, @{ returnCode = 3010; type = 'softReboot' }, @{ returnCode = 1641; type = 'hardReboot' }, @{ returnCode = 1618; type = 'retry' })
                }
                $AppBody = [ordered]@{
                    '@odata.type'                  = '#microsoft.graph.win32LobApp'
                    displayName                    = "$($AppConfig.Applicationname)"
                    description                    = "$($AppConfig.description)"
                    publisher                      = "$($AppConfig.publisher ?? $Package.MsiInfo.MsiPublisher)"
                    displayVersion                 = $AppConfig.displayVersion ?? $Package.MsiInfo.MsiProductVersion
                    notes                          = $Marker
                    fileName                       = $Package.FileName
                    setupFilePath                  = $Package.SetupFile
                    installCommandLine             = $AppConfig.installCommandLine
                    uninstallCommandLine           = $AppConfig.uninstallCommandLine
                    allowAvailableUninstall        = [bool]($AppConfig.allowAvailableUninstall ?? $true)
                    minimumSupportedWindowsRelease = $AppConfig.minimumSupportedWindowsRelease.value ?? $AppConfig.minimumSupportedWindowsRelease ?? '1607'
                    installExperience              = @{
                        runAsAccount          = $AppConfig.runAsAccount.value ?? $AppConfig.runAsAccount ?? 'system'
                        deviceRestartBehavior = $AppConfig.deviceRestartBehavior.value ?? $AppConfig.deviceRestartBehavior ?? 'basedOnReturnCode'
                        maxRunTimeInMinutes   = [int]($AppConfig.maxRunTimeInMinutes ?? 60)
                    }
                    rules                          = @($Detection)
                    returnCodes                    = $ReturnCodes
                }
                # arm64 is only expressible through allowedArchitectures
                if ('arm64' -in $Architectures) { $AppBody.applicableArchitectures = 'none'; $AppBody.allowedArchitectures = $Architectures -join ',' } else { $AppBody.applicableArchitectures = $Architectures -join ',' }
                if ($Package.MsiInfo.MsiProductCode) {
                    $AppBody.msiInformation = @{
                        productCode    = $Package.MsiInfo.MsiProductCode; productVersion = $Package.MsiInfo.MsiProductVersion; upgradeCode = $Package.MsiInfo.MsiUpgradeCode
                        requiresReboot = $Package.MsiInfo.MsiRequiresReboot -eq 'true'; publisher = $Package.MsiInfo.MsiPublisher; productName = $Package.Name
                        packageType    = switch ($Package.MsiInfo.MsiExecutionContext) { 'User' { 'perUser' } 'Any' { 'dualPurpose' } default { 'perMachine' } }
                    }
            }
            }
            if ($AppConfig.largeIcon) { $AppBody.largeIcon = @{ '@odata.type' = '#microsoft.graph.mimeContent'; type = $AppConfig.largeIconType ?? 'image/png'; value = $AppConfig.largeIcon } }

            $EncryptionInfo = @{}
            foreach ($Property in $Package.EncryptionInfo.PSObject.Properties) { $EncryptionInfo[$Property.Name] = $Property.Value }
            $ContentParams = @{
                BlobPath = "app-packages/$PackageId/IntunePackage.intunewin"; ConnectionString = $PackageStorage; EncryptedSize = [int64]$Package.EncryptedSize; FileName = $Package.FileName
                UnencryptedSize = [int64]$Package.UnencryptedContentSize; EncryptionInfo = $EncryptionInfo; TenantFilter = $TenantFilter; APIName = $APIName; AppType = $LobType
            }

            $Existing = @(New-GraphGetRequest -Uri "$BaseUri`?`$filter=isof('microsoft.graph.$LobType')&`$select=id,displayName,notes,createdDateTime" -tenantid $TenantFilter).Where({ $_.displayName -eq $AppConfig.Applicationname })
            if ($Existing.Where({ "$($_.notes)" -like "*$Marker*" }).Count -gt 0) {
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "$($AppConfig.Applicationname) is already on this package. Skipping this application" -Sev 'Info'
                return $null
            }
            $Previous = @($Existing | Sort-Object -Property createdDateTime -Descending)[0]

            # Supersedence exists only for Win32 apps; macOS packages always update in place.
            if ($Previous -and ($AppConfig.updateMode -ne 'supersede' -or $LobType -ne 'win32LobApp')) {
                # In place: new content version on the same app keeps its id, assignments and install history.
                $PreviousApp = New-GraphGetRequest -Uri "$BaseUri/$($Previous.id)" -tenantid $TenantFilter
                # Intune updates a macOS app only with the bundle ID it was created with.
                if ($LobType -ne 'win32LobApp' -and $PreviousApp.primaryBundleId -and $PreviousApp.primaryBundleId -ne $AppBody.primaryBundleId) {
                    throw "'$($AppConfig.Applicationname)' already exists for bundle ID $($PreviousApp.primaryBundleId), but this package is $($AppBody.primaryBundleId). Intune can only update a macOS app with the same bundle ID; give the template app a different name to deploy it as a new app."
                }
                $AppProperties = @{}
                foreach ($Key in $AppBody.Keys) { $AppProperties[$Key] = $AppBody[$Key] }
                if (-not $AppProperties.largeIcon -and $PreviousApp.largeIcon.value) {
                    $AppProperties.largeIcon = @{ '@odata.type' = '#microsoft.graph.mimeContent'; type = $PreviousApp.largeIcon.type; value = $PreviousApp.largeIcon.value }
                }
                $null = Add-CIPPWin32LobAppContent -AppId $Previous.id @ContentParams -AppProperties $AppProperties
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Updated $($AppConfig.Applicationname) to package $PackageId" -Sev 'Info'
                return $Previous
            }

            $NewApp = New-GraphPostRequest -Uri $BaseUri -tenantid $TenantFilter -Body (ConvertTo-Json -InputObject $AppBody -Depth 10) -Type POST
            try {
                $null = Add-CIPPWin32LobAppContent -AppId $NewApp.id @ContentParams
            } catch {
                # An app without committed content cannot be installed or edited; do not leave it behind.
                $null = New-GraphPostRequest -Uri "$BaseUri/$($NewApp.id)" -tenantid $TenantFilter -Type DELETE -Body ''
                throw
            }
            if ($Previous) {
                $Relationship = @{ relationships = @(@{ '@odata.type' = '#microsoft.graph.mobileAppSupersedence'; supersedenceType = $AppConfig.supersedenceType ?? 'update'; targetId = $Previous.id }) }
                $null = New-GraphPostRequest -Uri "$BaseUri/$($NewApp.id)/updateRelationships" -tenantid $TenantFilter -Type POST -Body (ConvertTo-Json -InputObject $Relationship -Depth 5)
                # The superseding app takes over targeting; leaving the old assignments would keep installing it.
                $null = New-GraphPostRequest -Uri "$BaseUri/$($Previous.id)/assign" -tenantid $TenantFilter -Type POST -Body '{"mobileAppAssignments":[]}'
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "$($AppConfig.Applicationname) package $PackageId supersedes app $($Previous.id) ($($Relationship.relationships[0].supersedenceType))" -Sev 'Info'
            }
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
                'EdgeApp' { $null }
                'MacOSPackageApp' { $null }
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
            # Group ids queued by the deploy drawer's single-tenant picker; they win over the
            # name resolution of assignTo/excludeGroup inside Set-CIPPAssignedApplication.
            # '@($null).Count' is 1, so test the value before counting it.
            if ($AppConfig.GroupIds -and @($AppConfig.GroupIds).Count -gt 0) { $AssignParams.GroupIds = @($AppConfig.GroupIds) }
            if ($AppConfig.ExcludeGroupIds -and @($AppConfig.ExcludeGroupIds).Count -gt 0) { $AssignParams.ExcludeGroupIds = @($AppConfig.ExcludeGroupIds) }
            Set-CIPPAssignedApplication @AssignParams
        }
    }

    return $NewApp
}
