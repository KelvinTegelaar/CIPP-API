function Get-CIPPReusableSettingsFromPolicy {
    param(
        [string]$PolicyJson,
        [string]$Tenant,
        $Headers,
        [string]$APIName
    )

    $result = [pscustomobject]@{
        ReusableSettings = [System.Collections.Generic.List[psobject]]::new()
    }

    if (-not $PolicyJson) { return $result }

    try {
        $policyObject = $PolicyJson | ConvertFrom-Json -Depth 300 -ErrorAction Stop
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Reusable settings discovery failed: policy JSON invalid ($($_.Exception.Message))" -Sev 'Warn'
        return $result
    }

    function Get-ReusableSettingIds {
        param(
            [Parameter(Mandatory = $true)]
            $PolicyObject
        )

        $ids = [System.Collections.Generic.List[string]]::new()

        function Get-ReusableSettingIdsFromValue {
            param(
                $Value,
                [string]$ParentName = ''
            )

            if ($null -eq $Value) { return }

            if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                foreach ($item in $Value) { Get-ReusableSettingIdsFromValue -Value $item -ParentName $ParentName }
                return
            }

            if ($Value -is [psobject]) {
                if ($Value.'@odata.type' -like '*ReferenceSettingValue' -and $Value.value -match '^[0-9a-fA-F-]{36}$') {
                    $ids.Add($Value.value)
                }

                if ($ParentName -eq 'simpleSettingCollectionValue' -and $Value.value -is [string] -and $Value.value -match '^[0-9a-fA-F-]{36}$') {
                    $ids.Add($Value.value)
                }

                foreach ($prop in $Value.PSObject.Properties) {
                    $name = $prop.Name
                    $propValue = $prop.Value

                    if ($name -match 'reusableSetting') {
                        if ($propValue -is [string] -and $propValue -match '^[0-9a-fA-F-]{36}$') { $ids.Add($propValue) }
                        elseif ($propValue -is [psobject] -and $propValue.id -match '^[0-9a-fA-F-]{36}$') { $ids.Add($propValue.id) }
                        elseif ($propValue -is [System.Collections.IEnumerable]) {
                            foreach ($entry in $propValue) {
                                if ($entry -is [string] -and $entry -match '^[0-9a-fA-F-]{36}$') { $ids.Add($entry) }
                                elseif ($entry -is [psobject] -and $entry.id -match '^[0-9a-fA-F-]{36}$') { $ids.Add($entry.id) }
                            }
                        }
                    }

                    Get-ReusableSettingIdsFromValue -Value $propValue -ParentName $name
                }
            }
        }

        Get-ReusableSettingIdsFromValue -Value $PolicyObject
        return $ids | Select-Object -Unique
    }

    $referencedReusableIds = Get-ReusableSettingIds -PolicyObject $policyObject
    Write-Information "ReusableSettings discovery: found $($referencedReusableIds.Count) ids -> $($referencedReusableIds -join ',')"

    if (-not $referencedReusableIds) { return $result }

    $templatesTable = Get-CippTable -tablename 'templates'
    $templatesTableForAdd = @{} + $templatesTable
    $templatesTableForAdd.Force = $true

    $existingReusableTemplates = @(Get-CIPPAzDataTableEntity @templatesTable -Filter "PartitionKey eq 'IntuneReusableSettingTemplate'")
    $existingReusableByName = @{}
    foreach ($templateEntry in $existingReusableTemplates) {
        $name = $templateEntry.DisplayName
        if (-not $name) {
            $parsed = $templateEntry.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
            $name = $parsed.DisplayName
        }
        if ($name -and -not $existingReusableByName.ContainsKey($name)) {
            $existingReusableByName[$name] = $templateEntry
        }
    }

    foreach ($settingId in $referencedReusableIds) {
        try {
            $setting = New-GraphGETRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings/$settingId" -tenantid $Tenant
            if ($null -eq $setting) {
                Write-LogMessage -headers $Headers -API $APIName -message "Reusable setting $settingId not returned from Graph" -Sev 'Warn'
                continue
            }

            # Normalize Graph SDK objects into PSCustomObject to ensure cleanup works consistently
            $settingNormalized = [ordered]@{}
            foreach ($prop in $setting.PSObject.Properties) {
                $settingNormalized[$prop.Name] = $prop.Value
            }

            if ($settingNormalized.Count -eq 0) {
                foreach ($prop in $setting.GetType().GetProperties()) {
                    $settingNormalized[$prop.Name] = $prop.GetValue($setting)
                }
            }

            $settingNormalized = $settingNormalized | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -Depth 100

            $settingDisplayName = $setting.displayName ?? $settingNormalized.displayName
            if (-not $settingDisplayName) {
                Write-LogMessage -headers $Headers -API $APIName -message "Reusable setting $settingId missing displayName" -Sev 'Warn'
                continue
            }

            $matchedTemplate = $existingReusableByName[$settingDisplayName]
            $templateGuid = $matchedTemplate.RowKey

            $cleanSetting = Remove-CIPPReusableSettingMetadata -InputObject $settingNormalized
            $sanitizedJson = $cleanSetting | ConvertTo-Json -Depth 100 -Compress

            if (-not $templateGuid) {
                $templateGuid = (New-Guid).Guid
                $reusableEntity = [pscustomobject]@{
                    DisplayName = $settingDisplayName
                    Description = $setting.description
                    RawJSON     = $sanitizedJson
                    GUID        = $templateGuid
                } | ConvertTo-Json -Depth 100 -Compress

                Add-CIPPAzDataTableEntity @templatesTableForAdd -Entity @{
                    JSON         = "$reusableEntity"
                    RowKey       = "$templateGuid"
                    PartitionKey = 'IntuneReusableSettingTemplate'
                    GUID         = "$templateGuid"
                    DisplayName  = $settingDisplayName
                }

                $existingReusableByName[$settingDisplayName] = [pscustomobject]@{
                    RowKey      = $templateGuid
                    DisplayName = $settingDisplayName
                    JSON        = $reusableEntity
                }

                Write-LogMessage -headers $Headers -API $APIName -message "Created reusable setting template $templateGuid for '$settingDisplayName'" -Sev 'Info'
            } else {
                $existingRawJson = $matchedTemplate.RawJSON
                if (-not $existingRawJson) {
                    $existingParsed = $matchedTemplate.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                    $existingRawJson = $existingParsed.RawJSON
                }

                $requiresNormalization = $false
                if ($existingRawJson -and $existingRawJson -match '"children"\s*:\s*null') {
                    $requiresNormalization = $true
                }

                if ($requiresNormalization) {
                    $reusableEntity = [pscustomobject]@{
                        DisplayName = $settingDisplayName
                        Description = $setting.description
                        RawJSON     = $sanitizedJson
                        GUID        = $templateGuid
                    } | ConvertTo-Json -Depth 100 -Compress

                    Add-CIPPAzDataTableEntity @templatesTableForAdd -Entity @{
                        JSON         = "$reusableEntity"
                        RowKey       = "$templateGuid"
                        PartitionKey = 'IntuneReusableSettingTemplate'
                        GUID         = "$templateGuid"
                        DisplayName  = $settingDisplayName
                        Description  = $setting.description
                        RawJSON      = "$sanitizedJson"
                    }

                    $existingReusableByName[$settingDisplayName] = [pscustomobject]@{
                        RowKey      = $templateGuid
                        DisplayName = $settingDisplayName
                        JSON        = $reusableEntity
                        RawJSON     = $sanitizedJson
                    }

                    Write-LogMessage -headers $Headers -API $APIName -message "Normalized reusable setting template $templateGuid for '$settingDisplayName'" -Sev 'Info'
                } else {
                    Write-LogMessage -headers $Headers -API $APIName -message "Reusing existing reusable setting template $templateGuid for '$settingDisplayName'" -Sev 'Info'
                }
            }

            $result.ReusableSettings.Add([pscustomobject]@{
                    displayName = $settingDisplayName
                    templateId  = $templateGuid
                    sourceId    = $settingId
                })
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to link reusable setting $settingId for template creation: $($_.Exception.Message)" -Sev 'Warn'
        }
    }

    Write-LogMessage -headers $Headers -API $APIName -message "Reusable settings mapped: $($result.ReusableSettings.Count) -> $($result.ReusableSettings.displayName -join ', ')" -Sev 'Info'
    return $result
}
