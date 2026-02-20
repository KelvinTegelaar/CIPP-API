function Push-UploadApplication {
    <#
        .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    try {
        $Table = Get-CippTable -tablename 'apps'
        $Filter = "PartitionKey eq 'apps' and RowKey eq '$($Item.Name)'"

        $ModuleRoot = (Get-Module CIPPCore).ModuleBase
        $CippRoot = (Get-Item $ModuleRoot).Parent.Parent
        Set-Location $CippRoot

        $AppConfig = (Get-CIPPAzDataTableEntity @Table -filter $Filter).JSON | ConvertFrom-Json
        $intuneBody = $AppConfig.IntuneBody
        $tenants = if ($AppConfig.tenant -eq 'AllTenants') {
            (Get-Tenants -IncludeErrors).defaultDomainName
        } else {
            $AppConfig.tenant
        }
        $assignTo = $AppConfig.assignTo
        $AssignToIntent = $AppConfig.InstallationIntent
        $ClearRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if ($AppConfig.tenant -ne 'AllTenants') {
            $null = Remove-AzDataTableEntity -Force @Table -Entity $clearRow
        } else {
            $Table.Force = $true
            $null = Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$($AppConfig | ConvertTo-Json)"
                RowKey       = "$($ClearRow.RowKey)"
                PartitionKey = 'apps'
                status       = 'Deployed'
            }
        }

        # Determine app type (default to 'Choco' if not specified)
        $AppType = if ($AppConfig.type) { $AppConfig.type } else { 'Choco' }

        # Load files based on app type (only for types that need them)
        $Intunexml = $null
        $Infile = $null
        if ($AppType -eq 'MSPApp') {
            [xml]$Intunexml = Get-Content "AddMSPApp\$($AppConfig.MSPAppName).app.xml"
            $Infile = "AddMSPApp\$($AppConfig.MSPAppName).intunewin"
        } elseif ($AppType -in @('Choco', 'Win32ScriptApp')) {
            [xml]$Intunexml = Get-Content 'AddChocoApp\Choco.App.xml'
            $Infile = "AddChocoApp\$($Intunexml.ApplicationInfo.FileName)"
        }


        $baseuri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
        foreach ($tenant in $tenants) {
            try {
                # Check if app already exists
                $ApplicationList = New-GraphGetRequest -Uri $baseuri -tenantid $tenant | Where-Object { $_.DisplayName -eq $AppConfig.Applicationname -and ($_.'@odata.type' -eq '#microsoft.graph.win32LobApp' -or $_.'@odata.type' -eq '#microsoft.graph.winGetApp') }
                if ($ApplicationList.displayname.count -ge 1) {
                    Write-LogMessage -api 'AppUpload' -tenant $tenant -message "$($AppConfig.Applicationname) exists. Skipping this application" -Sev 'Info'
                    continue
                }

                # Route to appropriate handler based on app type
                $NewApp = $null
                switch ($AppType) {
                    'WinGet' {
                        $NewApp = Add-CIPPWinGetApp -AppBody $intuneBody -TenantFilter $tenant
                    }
                    'Choco' {
                        # Prepare encryption info from XML
                        $EncryptionInfo = @{
                            EncryptionKey        = $Intunexml.ApplicationInfo.EncryptionInfo.EncryptionKey
                            MacKey               = $Intunexml.ApplicationInfo.EncryptionInfo.MacKey
                            InitializationVector = $Intunexml.ApplicationInfo.EncryptionInfo.InitializationVector
                            Mac                  = $Intunexml.ApplicationInfo.EncryptionInfo.Mac
                            ProfileIdentifier    = $Intunexml.ApplicationInfo.EncryptionInfo.ProfileIdentifier
                            FileDigest           = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigest
                            FileDigestAlgorithm  = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigestAlgorithm
                        }

                        # Build parameters dynamically
                        $Params = @{
                            AppBody         = $intuneBody
                            TenantFilter    = $tenant
                            FilePath        = $Infile
                            FileName        = $Intunexml.ApplicationInfo.FileName
                            UnencryptedSize = [int64]$Intunexml.ApplicationInfo.UnencryptedContentSize
                            EncryptionInfo  = $EncryptionInfo
                        }
                        if ($AppConfig.Applicationname) { $Params.DisplayName = $AppConfig.Applicationname }

                        $NewApp = Add-CIPPPackagedApplication @Params
                    }
                    'MSPApp' {
                        # Prepare encryption info from XML
                        $EncryptionInfo = @{
                            EncryptionKey        = $Intunexml.ApplicationInfo.EncryptionInfo.EncryptionKey
                            MacKey               = $Intunexml.ApplicationInfo.EncryptionInfo.MacKey
                            InitializationVector = $Intunexml.ApplicationInfo.EncryptionInfo.InitializationVector
                            Mac                  = $Intunexml.ApplicationInfo.EncryptionInfo.Mac
                            ProfileIdentifier    = $Intunexml.ApplicationInfo.EncryptionInfo.ProfileIdentifier
                            FileDigest           = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigest
                            FileDigestAlgorithm  = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigestAlgorithm
                        }

                        # Build parameters dynamically
                        $Params = @{
                            AppBody         = $intuneBody
                            TenantFilter    = $tenant
                            FilePath        = $Infile
                            FileName        = $Intunexml.ApplicationInfo.FileName
                            UnencryptedSize = [int64]$Intunexml.ApplicationInfo.UnencryptedContentSize
                            EncryptionInfo  = $EncryptionInfo
                        }
                        if ($AppConfig.Applicationname) { $Params.DisplayName = $AppConfig.Applicationname }

                        $NewApp = Add-CIPPPackagedApplication @Params
                    }
                    'Win32ScriptApp' {
                        # Prepare encryption info from XML
                        $EncryptionInfo = @{
                            EncryptionKey        = $Intunexml.ApplicationInfo.EncryptionInfo.EncryptionKey
                            MacKey               = $Intunexml.ApplicationInfo.EncryptionInfo.MacKey
                            InitializationVector = $Intunexml.ApplicationInfo.EncryptionInfo.InitializationVector
                            Mac                  = $Intunexml.ApplicationInfo.EncryptionInfo.Mac
                            ProfileIdentifier    = $Intunexml.ApplicationInfo.EncryptionInfo.ProfileIdentifier
                            FileDigest           = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigest
                            FileDigestAlgorithm  = $Intunexml.ApplicationInfo.EncryptionInfo.FileDigestAlgorithm
                        }

                        # Build properties dynamically
                        $Properties = @{
                            displayName   = $AppConfig.Applicationname
                            installScript = $AppConfig.installScript
                        }

                        # A few of these are probably mandatory
                        if ($AppConfig.description) { $Properties['description'] = $AppConfig.description }
                        if ($AppConfig.publisher) { $Properties['publisher'] = $AppConfig.publisher }
                        if ($AppConfig.uninstallScript) { $Properties['uninstallScript'] = $AppConfig.uninstallScript }
                        if ($AppConfig.detectionPath) { $Properties['detectionPath'] = $AppConfig.detectionPath }
                        if ($AppConfig.detectionFile) { $Properties['detectionFile'] = $AppConfig.detectionFile }
                        if ($AppConfig.runAsAccount) { $Properties['runAsAccount'] = $AppConfig.runAsAccount }
                        if ($AppConfig.deviceRestartBehavior) { $Properties['deviceRestartBehavior'] = $AppConfig.deviceRestartBehavior }
                        if ($null -ne $AppConfig.runAs32Bit) { $Properties['runAs32Bit'] = $AppConfig.runAs32Bit }
                        if ($null -ne $AppConfig.enforceSignatureCheck) { $Properties['enforceSignatureCheck'] = $AppConfig.enforceSignatureCheck }

                        $NewApp = Add-CIPPW32ScriptApplication -TenantFilter $tenant -Properties ([PSCustomObject]$Properties)
                    }
                    'WinGetNew' {
                        # I think we don't need a separate WinGetNew type, just use WinGet?
                    }
                    default {
                        throw "Unsupported app type: $($AppConfig.type)"
                    }
                }

                # Log success and assign app if requested
                if ($NewApp) {
                    Write-LogMessage -api 'AppUpload' -tenant $tenant -message "$($AppConfig.Applicationname) Successfully created" -Sev 'Info'

                    if ($assignTo -and $assignTo -ne 'On') {
                        $intent = if ($AssignToIntent) { 'Uninstall' } else { 'Required' }
                        $AppTypeForAssignment = switch ($AppType) {
                            'WinGet' { 'WinGet' }
                            'WinGetNew' { 'WinGet' }
                            default { 'Win32Lob' }
                        }
                        Start-Sleep -Milliseconds 200
                        Set-CIPPAssignedApplication -ApplicationId $NewApp.Id -TenantFilter $tenant -groupName $assignTo -Intent $intent -AppType $AppTypeForAssignment -APIName 'AppUpload'
                    }
                }
            } catch {
                "Failed to add Application for $tenant : $($_.Exception.Message)"
                Write-LogMessage -api 'AppUpload' -tenant $tenant -message "Failed adding Application $($AppConfig.Applicationname). Error: $($_.Exception.Message)" -LogData (Get-CippException -Exception $_) -Sev 'Error'
                continue
            }
        }
    } catch {
        Write-Host "Error pushing application: $($_.Exception.Message)"
    }
}
