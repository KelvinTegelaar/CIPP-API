function ConvertTo-CIPPIntunePolicySetting {
    <#
    .SYNOPSIS
        Flattens one cached Intune policy into searchable setting rows.
    .DESCRIPTION
        Settings catalog policies yield one row per setting instance, including nested children.
        Custom policies yield one row per OMA-URI. Other policies yield one row per configured
        property, skipping metadata and unset values. Each row has SettingId, SettingName, Category and Value.
    .PARAMETER Policy
        The policy object as cached by Set-CIPPDBCacheIntunePolicies.
    .PARAMETER URLName
        The policy family Id from Get-CIPPIntunePolicyListDefinitions.
    .PARAMETER PolicyTypeName
        The policy type label, used as the category when the catalog has none.
    .PARAMETER DefinitionIndex
        The index from Get-CIPPIntuneDefinitionIndex. Catalog rows fall back to raw ids without it.
    .PARAMETER Search
        Only return rows whose SettingName or SettingId contains this text, case-insensitively.
    .PARAMETER SettingIds
        Only return rows with one of these SettingIds.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Policy,

        [string]$URLName,

        [AllowNull()]
        [string]$PolicyTypeName,

        [AllowNull()]
        $DefinitionIndex,

        [string]$Search,

        [AllowNull()]
        [System.Collections.Generic.HashSet[string]]$SettingIds
    )

    if ($null -eq $Policy) { return }

    $MaxValueLength = 500
    $MaxDepth = 4
    $IgnoreCase = [System.StringComparison]::OrdinalIgnoreCase

    # Graph returns some credentials in plain text (pre-shared keys, kiosk exit codes, key/value app settings)
    $SecretNamePattern = '(?i)(password|passphrase|passcode|presharedkey|sharedsecret|secret|privatekey|apikey|keymaterial|token|exitcode)$'
    $HiddenProperties = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('payload', 'payloadJson', 'customXml', 'encodedSettingXml', 'configurationXml'),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    # SettingId, SettingName, Category, raw value
    $Found = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $Policy.settings -and @($Policy.settings).Where({ $_.settingInstance }).Count -gt 0) {
        $WalkInstance = $null
        $WalkInstance = {
            param($Instance)
            if ($null -eq $Instance) { return }
            $DefinitionId = [string]$Instance.settingDefinitionId
            $Definition = if ($DefinitionIndex -and $DefinitionId) { $DefinitionIndex[$DefinitionId] } else { $null }
            $SettingName = [string]$Definition.displayName
            if ([string]::IsNullOrWhiteSpace($SettingName)) { $SettingName = $DefinitionId }
            $Wanted = $DefinitionId -and ($null -eq $SettingIds -or $SettingIds.Contains($DefinitionId)) -and
            (-not $Search -or $SettingName.Contains($Search, $IgnoreCase) -or $DefinitionId.Contains($Search, $IgnoreCase))
            $Children = [System.Collections.Generic.List[object]]::new()
            $Value = $null

            switch -Wildcard ([string]$Instance.'@odata.type') {
                '*ChoiceSettingCollectionInstance' {
                    $Labels = [System.Collections.Generic.List[string]]::new()
                    foreach ($Choice in @($Instance.choiceSettingCollectionValue)) {
                        if ($null -eq $Choice) { continue }
                        foreach ($Child in @($Choice.children)) { if ($Child) { $Children.Add($Child) } }
                        if (-not $Wanted -or $null -eq $Choice.value) { continue }
                        $Label = $null
                        if (-not ($Definition -and $Definition.options -and $Definition.options.TryGetValue("$($Choice.value)", [ref]$Label) -and $Label)) { $Label = "$($Choice.value)" }
                        if ($Label) { $Labels.Add($Label) }
                    }
                    $Value = $Labels -join ', '
                }
                '*ChoiceSettingInstance' {
                    foreach ($Child in @($Instance.choiceSettingValue.children)) { if ($Child) { $Children.Add($Child) } }
                    $Option = $Instance.choiceSettingValue.value
                    if ($Wanted -and $null -ne $Option) {
                        $Label = $null
                        $Value = if ($Definition -and $Definition.options -and $Definition.options.TryGetValue("$Option", [ref]$Label) -and $Label) { $Label } else { "$Option" }
                    }
                }
                '*SimpleSettingCollectionInstance' {
                    if ($Wanted) {
                        $Parts = [System.Collections.Generic.List[object]]::new()
                        foreach ($Item in @($Instance.simpleSettingCollectionValue)) {
                            if ($null -eq $Item) { continue }
                            if ($Item.'@odata.type' -like '*SecretSettingValue') { $Parts.Add('(secret)'); continue }
                            foreach ($Part in $Item.value) { if ($null -ne $Part) { $Parts.Add($Part) } }
                        }
                        $Value = $Parts -join ', '
                    }
                }
                '*SimpleSettingInstance' {
                    $SimpleValue = $Instance.simpleSettingValue
                    if ($null -ne $SimpleValue) {
                        $Value = if ($SimpleValue.'@odata.type' -like '*SecretSettingValue') { '(secret)' } else { $SimpleValue.value }
                    }
                }
                '*GroupSettingCollectionInstance' {
                    $ItemCount = 0
                    foreach ($Item in $Instance.groupSettingCollectionValue) {
                        if ($null -eq $Item) { continue }
                        $ItemCount++
                        foreach ($Child in @($Item.children)) { if ($Child) { $Children.Add($Child) } }
                    }
                    $Value = if ($ItemCount -eq 1) { '1 item' } else { "$ItemCount items" }
                }
                '*GroupSettingInstance' {
                    foreach ($Child in @($Instance.groupSettingValue.children)) { if ($Child) { $Children.Add($Child) } }
                    $Value = 'Configured'
                }
            }

            if ($Wanted) { $Found.Add(@($DefinitionId, $SettingName, $Definition.categoryName, $Value)) }
            foreach ($Child in $Children) { & $WalkInstance $Child }
        }

        foreach ($Setting in @($Policy.settings)) {
            if ($null -eq $Setting) { continue }
            & $WalkInstance $Setting.settingInstance
        }
    } else {
        $PlainOmaTypes = @('omaSettingInteger', 'omaSettingBoolean', 'omaSettingFloatingPoint', 'omaSettingDateTime')
        foreach ($OmaSetting in @($Policy.omaSettings)) {
            if ($null -eq $OmaSetting -or [string]::IsNullOrWhiteSpace($OmaSetting.omaUri)) { continue }
            $SettingId = [string]$OmaSetting.omaUri
            $SettingName = [string]$OmaSetting.displayName
            if ([string]::IsNullOrWhiteSpace($SettingName)) { $SettingName = $SettingId }
            if ($null -ne $SettingIds -and -not $SettingIds.Contains($SettingId)) { continue }
            if ($Search -and -not ($SettingName.Contains($Search, $IgnoreCase) -or $SettingId.Contains($Search, $IgnoreCase))) { continue }
            # The cache stores OMA settings decrypted and without isEncrypted, so only types Intune never encrypts are shown
            $OmaType = ([string]$OmaSetting.'@odata.type') -replace '^#?microsoft\.graph\.', ''
            $Value = if ($OmaType -notin $PlainOmaTypes -or $OmaSetting.isEncrypted -or $OmaSetting.secretReferenceValueId) { '(encrypted)' } else { $OmaSetting.value }
            $Found.Add(@($SettingId, $SettingName, $null, $Value))
        }

        $ODataType = ([string]$Policy.'@odata.type') -replace '^#?microsoft\.graph\.', ''
        $TypePrefix = if ($ODataType) { $ODataType } else { $URLName }

        $SkippedProperties = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
                'id', 'displayName', 'name', 'description', 'version', 'createdDateTime', 'lastModifiedDateTime',
                'roleScopeTagIds', 'assignments', 'supportsScopeTags', 'isAssigned', 'settings', 'settingCount',
                'omaSettings', 'deviceManagementApplicabilityRuleOsEdition', 'deviceManagementApplicabilityRuleOsVersion',
                'deviceManagementApplicabilityRuleDeviceMode', 'createdBy', 'lastModifiedBy', 'deployedAppCount',
                'templateReference', 'creationSource', 'platforms', 'technologies', 'priorityMetaData',
                'PolicyTypeName', 'URLName', 'PolicyAssignment', 'PolicyExclude', 'Tenant', 'CacheTimestamp'
            ), [System.StringComparer]::OrdinalIgnoreCase)

        # Graph returns every property of these policies: unset booleans come back false and unset enums as these members
        $UnsetValues = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@('notConfigured', 'userDefined', 'deviceDefault', 'browserDefault'),
            [System.StringComparer]::OrdinalIgnoreCase
        )

        $Redact = $null
        $Redact = {
            param($Value)
            if ($Value -is [System.Management.Automation.PSCustomObject]) {
                $Copy = [ordered]@{}
                foreach ($Property in $Value.PSObject.Properties) {
                    $Name = $Property.Name
                    $Inner = $Property.Value
                    $Copy[$Name] = if ($Inner -is [bool]) {
                        $Inner
                    } elseif ($HiddenProperties.Contains($Name)) {
                        '(hidden)'
                    } elseif ($Name -match $SecretNamePattern -or ($Name -eq 'value' -and [string]($Value.name ?? $Value.key) -match $SecretNamePattern)) {
                        '(secret)'
                    } else {
                        & $Redact $Inner
                    }
                }
                return [PSCustomObject]$Copy
            }
            if ($Value -isnot [string] -and $Value -is [System.Collections.IEnumerable]) {
                return , @(foreach ($Item in $Value) { & $Redact $Item })
            }
            $Value
        }

        $WalkProperties = $null
        $WalkProperties = {
            param($Object, [string]$IdPath, [string]$NamePath, [int]$Depth)
            foreach ($Property in $Object.PSObject.Properties) {
                $PropertyName = $Property.Name
                if ($PropertyName -like '*@odata*') { continue }
                if ($Depth -eq 0 -and $SkippedProperties.Contains($PropertyName)) { continue }

                $Value = $Property.Value
                if ($null -eq $Value) { continue }
                if ($Value -is [bool] -and -not $Value) { continue }
                if ($Value -is [string] -and ([string]::IsNullOrWhiteSpace($Value) -or $UnsetValues.Contains($Value))) { continue }

                $SettingId = "$IdPath/$PropertyName"
                $IsObject = $Value -is [System.Management.Automation.PSCustomObject] -and $Depth -lt $MaxDepth
                $Wanted = $null -eq $SettingIds -or $SettingIds.Contains($SettingId)
                if (-not $Wanted -and -not $IsObject) { continue }

                $Spaced = ($PropertyName -creplace '([a-z\d])([A-Z])', '$1 $2') -creplace '([A-Z]+)([A-Z][a-z])', '$1 $2'
                $Words = foreach ($Word in ($Spaced -split '[\s_]+')) {
                    if (-not $Word) { continue }
                    if ($Word -cmatch '^[A-Z][a-z\d]*$') { $Word.ToLowerInvariant() } else { $Word }
                }
                $Humanised = $Words -join ' '
                if ($Humanised) { $Humanised = $Humanised.Substring(0, 1).ToUpperInvariant() + $Humanised.Substring(1) }
                $SettingName = if ($NamePath) { "$NamePath > $Humanised" } else { $Humanised }
                if ([string]::IsNullOrWhiteSpace($SettingName)) { $SettingName = $SettingId }

                if ($Wanted -and $Search -and -not ($SettingName.Contains($Search, $IgnoreCase) -or $SettingId.Contains($Search, $IgnoreCase))) {
                    if (-not $IsObject) { continue }
                    $Wanted = $false
                }

                $Marker = if ($Value -is [bool]) {
                    $null
                } elseif ($HiddenProperties.Contains($PropertyName)) {
                    '(hidden)'
                } elseif ($PropertyName -match $SecretNamePattern -or ($PropertyName -eq 'value' -and [string]($Object.name ?? $Object.key) -match $SecretNamePattern)) {
                    '(secret)'
                }
                if ($Marker) {
                    if ($Wanted) { $Found.Add(@($SettingId, $SettingName, $null, $Marker)) }
                    continue
                }
                if ($IsObject) {
                    & $WalkProperties $Value $SettingId $SettingName ($Depth + 1)
                    continue
                }
                if ($Value -isnot [string] -and $Value -is [System.Collections.IEnumerable]) {
                    $HasItem = $false
                    foreach ($Item in $Value) { if ($null -ne $Item) { $HasItem = $true; break } }
                    if (-not $HasItem) { continue }
                    $Value = & $Redact $Value
                } elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
                    $Value = & $Redact $Value
                }
                $Found.Add(@($SettingId, $SettingName, $null, $Value))
            }
        }

        & $WalkProperties $Policy $TypePrefix $null 0
    }

    foreach ($Row in $Found) {
        $Value = $Row[3]
        $Text = if ($Value -is [string]) {
            $Value
        } elseif ($Value -is [bool]) {
            $Value.ToString().ToLowerInvariant()
        } elseif ($Value -is [System.Collections.IEnumerable]) {
            @(foreach ($Item in $Value) {
                    if ($null -eq $Item) { continue }
                    if ($Item -is [string] -or $Item -is [ValueType]) {
                        "$Item"
                    } else {
                        [CIPP.CippJson]::ToJson($Item, 5) ?? ($Item | ConvertTo-Json -Depth 5 -Compress -WarningAction SilentlyContinue)
                    }
                }) -join ', '
        } elseif ($Value -is [ValueType]) {
            "$Value"
        } else {
            [CIPP.CippJson]::ToJson($Value, 5) ?? ($Value | ConvertTo-Json -Depth 5 -Compress -WarningAction SilentlyContinue)
        }
        if ($Text.Length -gt $MaxValueLength) { $Text = $Text.Substring(0, $MaxValueLength) + '...' }
        [PSCustomObject]@{
            SettingId   = $Row[0]
            SettingName = $Row[1]
            Category    = if ([string]::IsNullOrWhiteSpace($Row[2])) { [string]$PolicyTypeName } else { [string]$Row[2] }
            Value       = [string]$Text
        }
    }
}
