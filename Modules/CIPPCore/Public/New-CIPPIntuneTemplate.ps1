function New-CIPPIntuneTemplate {
    param(
        $urlname,
        $id,
        $TenantFilter,
        $ActionResults,
        $CIPPURL,
        $ODataType
    )
    # App Protection and MAM App Configuration list rows (Invoke-ListAppProtectionPolicies) carry the
    # concrete @odata.type as their URLName. Map it into the managedAppPolicies bucket and derive
    # $ODataType so that branch fetches from the correct concrete collection - the generic
    # managedAppPolicies collection rejects a fetch-by-id for an app configuration policy ("Invalid Id").
    $ManagedAppPolicyTypes = @(
        'androidManagedAppProtection', 'iosManagedAppProtection', 'windowsManagedAppProtection',
        'mdmWindowsInformationProtectionPolicy', 'targetedManagedAppConfiguration', 'defaultManagedAppProtection'
    )
    if ($URLName -in $ManagedAppPolicyTypes) {
        if (-not $ODataType) { $ODataType = "#microsoft.graph.$URLName" }
        $URLName = 'managedAppPolicies'
    }
    if ($ODataType) {
        switch -wildcard ($ODataType) {
            '*CompliancePolicy' {
                $URLName = 'deviceCompliancePolicies'
            }
            '*managedAppPolicies' {
                $URLName = 'managedAppPolicies'
            }
            '*configurationPolicies' {
                $URLName = 'configurationPolicies'
            }
            '*windowsDriverUpdateProfiles' {
                $URLName = 'windowsDriverUpdateProfiles'
            }
            '*deviceConfigurations' {
                $URLName = 'deviceConfigurations'
            }
            '*groupPolicyConfigurations' {
                $URLName = 'groupPolicyConfigurations'
            }
            '*hardwareConfiguration' {
                $URLName = 'hardwareConfigurations'
            }
        }
    }
    switch ($URLName) {
        'deviceCompliancePolicies' {
            $Type = 'deviceCompliancePolicies'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)?`$expand=scheduledActionsForRule(`$expand=scheduledActionConfigurations)" -tenantid $TenantFilter
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'managedAppPolicies' {
            $Type = 'AppProtection'
            $AppProtectionUrl = switch (($ODataType -replace '#microsoft.graph.', '')) {
                'androidManagedAppProtection' { 'androidManagedAppProtections' }
                'iosManagedAppProtection' { 'iosManagedAppProtections' }
                'windowsManagedAppProtection' { 'windowsManagedAppProtections' }
                'mdmWindowsInformationProtectionPolicy' { 'mdmWindowsInformationProtectionPolicies' }
                'targetedManagedAppConfiguration' { 'targetedManagedAppConfigurations' }
                default { 'managedAppPolicies' }
            }
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$($AppProtectionUrl)('$($ID)')" -tenantid $TenantFilter
            if ($ODataType -and !$Template.'@odata.type') {
                # Graph omits @odata.type when an entity is fetched via its concrete type URL, but Set-CIPPIntunePolicy derives the deploy URL from it
                if ($ODataType -notmatch '^#') { $ODataType = "#$ODataType" }
                $null = $Template | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value $ODataType -Force
            }
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'mobileAppConfigurations' {
            $Type = 'AppConfiguration'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/$($urlname)('$($ID)')" -tenantid $TenantFilter
            # targetedMobileApps are mobileApp ids, which only mean something in the tenant the
            # policy was captured from - deploying them elsewhere fails with an unknown app. Record
            # each app's identity (bundle / package id, name, type) so deployment can find the same
            # app in the target tenant. See Resolve-CIPPIntuneTargetedMobileApps.
            $TargetedAppDetails = foreach ($AppId in @($Template.targetedMobileApps | Where-Object { $_ })) {
                try {
                    $App = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId" -tenantid $TenantFilter
                    [PSCustomObject]@{
                        id                = $App.id
                        displayName       = $App.displayName
                        '@odata.type'     = $App.'@odata.type'
                        bundleId          = $App.bundleId
                        packageId         = $App.packageId
                        packageIdentifier = $App.packageIdentifier
                        appStoreUrl       = $App.appStoreUrl
                    }
                } catch {
                    Write-Warning "Could not read targeted app $AppId for app configuration '$($Template.displayName)': $($_.Exception.Message)"
                }
            }
            if ($TargetedAppDetails) {
                $Template | Add-Member -NotePropertyName 'targetedMobileAppsDetails' -NotePropertyValue @($TargetedAppDetails) -Force
            }
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'configurationPolicies' {
            $Type = 'Catalog'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')?`$expand=settings" -tenantid $TenantFilter | Select-Object name, description, settings, platforms, technologies, templateReference
            # Apple enrollment (ADE) policies deploy only with a creationSource binding them to the
            # target tenant's ADE token ("DepTokenId_{tokenId}"). That id is per tenant, so strip the
            # source tenant's token and store a %ADETokenId% placeholder the deploy resolves from the
            # target tenant's custom variable (see Get-CIPPTextReplacement / Set-CIPPIntunePolicy).
            if ($Template.templateReference.templateFamily -like 'enrollment*' -or $Template.technologies -match 'enrollment') {
                $Template | Add-Member -NotePropertyName 'creationSource' -NotePropertyValue 'DepTokenId_%ADETokenId%' -Force
            }
            $TemplateJson = $Template | ConvertTo-Json -Depth 100 -Compress
            $DisplayName = $Template.name

        }
        'windowsDriverUpdateProfiles' {
            $Type = 'windowsDriverUpdateProfiles'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $TenantFilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'deviceConfigurations' {
            $Type = 'Device'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $TenantFilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'

            # Check for and decrypt encrypted OMA settings
            if ($Template.omaSettings) {
                Write-Information "Checking for encrypted OMA settings in policy: $($Template.displayName)"
                $Template = Get-CIPPOmaSettingDecryptedValue -DeviceConfiguration $Template -DeviceConfigurationId $ID -TenantFilter $TenantFilter
            }

            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'groupPolicyConfigurations' {
            $Type = 'Admin'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)('$($ID)')" -tenantid $TenantFilter
            $DisplayName = $Template.displayName
            # Each setting's identity (name, category, class, presentation position) is recorded next
            # to its bind: a definition from an imported ADMX file has a different id in every tenant,
            # and the identity is what Resolve-CIPPIntuneAdminTemplateBinding matches on at deployment.
            $inputvar = Get-CIPPIntuneAdminTemplateDefinitionValue -PolicyId $ID -TenantFilter $TenantFilter -IncludeIdentity
            $TemplateJson = (ConvertTo-Json -InputObject $inputvar -Depth 100 -Compress)
        }
        'windowsFeatureUpdateProfiles' {
            $Type = 'windowsFeatureUpdateProfiles'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $TenantFilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'windowsQualityUpdatePolicies' {
            $Type = 'windowsQualityUpdatePolicies'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $TenantFilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'windowsQualityUpdateProfiles' {
            $Type = 'windowsQualityUpdateProfiles'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $TenantFilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
        'hardwareConfigurations' {
            $Type = 'hardwareConfigurations'
            $Template = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/$($urlname)/$($ID)" -tenantid $TenantFilter | Select-Object * -ExcludeProperty id, lastModifiedDateTime, '@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime'
            $DisplayName = $Template.displayName
            $TemplateJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress
        }
    }
    return [PSCustomObject]@{
        TemplateJson = $TemplateJson
        DisplayName  = $DisplayName
        Description  = $Template.description
        Type         = $Type
    }
}
