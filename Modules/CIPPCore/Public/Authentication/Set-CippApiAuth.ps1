function Set-CippApiAuth {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RGName,
        [string]$FunctionAppName,
        [string]$TenantId,
        [string[]]$ClientIds
    )

    if ($env:CIPPNG) {
        # Read-modify-write — only patch allowedApplications + allowedAudiences,
        # preserving the SSO EasyAuth config (clientSecretSettingName, excludedPaths, tokenStore, etc.)

        # Resolve env vars directly (same pattern as Set-CIPPSSOEasyAuth which works)
        $SiteName = $env:WEBSITE_SITE_NAME
        $ResourceGroup = $env:WEBSITE_RESOURCE_GROUP
        $SubscriptionId = if ($env:WEBSITE_OWNER_NAME) { ($env:WEBSITE_OWNER_NAME -split '\+')[0] } else { $null }

        Write-Information "[ApiAuth] SiteName=$SiteName, ResourceGroup=$ResourceGroup, SubscriptionId=$SubscriptionId"
        Write-Information "[ApiAuth] ClientIds to set: $($ClientIds -join ', ')"

        if (-not $SiteName -or -not $ResourceGroup -or -not $SubscriptionId) {
            throw "[ApiAuth] Missing App Service env vars: WEBSITE_SITE_NAME=$SiteName, WEBSITE_RESOURCE_GROUP=$ResourceGroup, SubscriptionId=$SubscriptionId"
        }

        $BaseUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$SiteName"
        Write-Information "[ApiAuth] BaseUri=$BaseUri"

        # Read current authsettingsV2 from platform-injected env var (reliable, no ARM call needed)
        # Then convert to deep hashtable for safe mutation
        if (-not $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
            throw '[ApiAuth] WEBSITE_AUTH_V2_CONFIG_JSON env var not set — EasyAuth may not be configured yet.'
        }

        $Current = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -AsHashtable -Depth 20
        # Wrap in properties envelope for the ARM PUT (env var has the raw config, ARM expects {properties: ...})
        $ArmPayload = @{ properties = $Current }

        Write-Information "[ApiAuth] Read config from env var OK. Keys=$($Current.Keys -join ', ')"

        # The env var has the raw config (identityProviders at top level, no properties wrapper)
        # Safely navigate/create the full path — any level may be null
        if (-not $Current.ContainsKey('identityProviders') -or $null -eq $Current.identityProviders) { $Current.identityProviders = @{} }
        if (-not $Current.identityProviders.ContainsKey('azureActiveDirectory') -or $null -eq $Current.identityProviders.azureActiveDirectory) { $Current.identityProviders.azureActiveDirectory = @{} }

        $AAD = $Current.identityProviders.azureActiveDirectory
        Write-Information "[ApiAuth] AAD keys: $($AAD.Keys -join ', ')"

        # The SSO app's clientId is the registration clientId — always keep it in the lists
        $SSOClientId = $AAD.registration.clientId
        Write-Information "[ApiAuth] SSO clientId from registration: $SSOClientId"

        # Merge: SSO app + all enabled API clients
        $AllAppIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($SSOClientId) { [void]$AllAppIds.Add($SSOClientId) }
        foreach ($id in $ClientIds) {
            if (-not [string]::IsNullOrEmpty($id)) { [void]$AllAppIds.Add($id) }
        }

        # Build allowed audiences: api://{id} for each
        $AllAudiences = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($id in $AllAppIds) {
            [void]$AllAudiences.Add("api://$id")
        }

        Write-Information "[ApiAuth] Merged allowedApplications: $($AllAppIds -join ', ')"
        Write-Information "[ApiAuth] Merged allowedAudiences: $($AllAudiences -join ', ')"

        # Ensure every level of the validation path exists
        if (-not $AAD.ContainsKey('validation') -or $null -eq $AAD.validation) {
            $AAD.validation = @{}
        }
        $AAD.validation.allowedAudiences = @($AllAudiences)

        if (-not $AAD.validation.ContainsKey('defaultAuthorizationPolicy') -or $null -eq $AAD.validation.defaultAuthorizationPolicy) {
            $AAD.validation.defaultAuthorizationPolicy = @{}
        }
        $AAD.validation.defaultAuthorizationPolicy.allowedApplications = @($AllAppIds)

        # Ensure allowedPrincipals exists (for "use default restrictions based on issuer")
        if (-not $AAD.validation.defaultAuthorizationPolicy.ContainsKey('allowedPrincipals')) {
            $AAD.validation.defaultAuthorizationPolicy.allowedPrincipals = @{}
        }

        $PutBody = $ArmPayload | ConvertTo-Json -Depth 20
        Write-Information "[ApiAuth] PUT body: $PutBody"

        if ($PSCmdlet.ShouldProcess('Update authsettingsV2 (read-modify-write)')) {
            $PutUri = "$BaseUri/config/authsettingsV2?api-version=2020-06-01"
            $PutResult = New-CIPPAzRestRequest -Uri $PutUri -Method PUT -Body $PutBody -ContentType 'application/json' -ErrorAction Stop
            Write-Information "[ApiAuth] PUT result: $($PutResult | ConvertTo-Json -Depth 10 -Compress)"
            Write-Information "[ApiAuth] Updated EasyAuth successfully"
        }
    } else {
        # Full overwrite path (no SSO EasyAuth config to preserve)
        $SubscriptionId = Get-CIPPAzFunctionAppSubId
        $BaseUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$FunctionAppName"

        $getUri = "$BaseUri/config/authsettingsV2/list?api-version=2020-06-01"
        $AuthSettings = New-CIPPAzRestRequest -Uri $getUri -Method POST

        Write-Information "AuthSettings: $($AuthSettings | ConvertTo-Json -Depth 10)"

        $AllowedAudiences = foreach ($ClientId in $ClientIds) { "api://$ClientId" }
        if (!$AllowedAudiences) { $AllowedAudiences = @() }
        if (!$ClientIds) { $ClientIds = @() }

        if (($ClientIds | Measure-Object).Count -gt 0) {
            $AuthSettings.properties.identityProviders.azureActiveDirectory = @{
                enabled      = $true
                registration = @{
                    clientId     = $ClientIds[0] ?? $ClientIds
                    openIdIssuer = "https://sts.windows.net/$TenantID/v2.0"
                }
                validation   = @{
                    allowedAudiences           = @($AllowedAudiences)
                    defaultAuthorizationPolicy = @{
                        allowedApplications = @($ClientIds)
                    }
                }
            }
        } else {
            $AuthSettings.properties.identityProviders.azureActiveDirectory = @{
                enabled      = $false
                registration = @{}
                validation   = @{}
            }
        }

        $AuthSettings.properties.globalValidation = @{
            unauthenticatedClientAction = 'Return401'
        }
        $AuthSettings.properties.login = @{
            tokenStore = @{
                enabled                    = $true
                tokenRefreshExtensionHours = 72
            }
        }

        if ($PSCmdlet.ShouldProcess('Update auth settings')) {
            $putUri = "$BaseUri/config/authsettingsV2?api-version=2020-06-01"
            $Body = $AuthSettings | ConvertTo-Json -Depth 20
            $null = New-CIPPAzRestRequest -Uri $putUri -Method PUT -Body $Body -ContentType 'application/json'
        }

        if ($PSCmdlet.ShouldProcess('Update allowed tenants')) {
            $null = Update-CIPPAzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $RGName -AppSetting @{ 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS' = $TenantId }
        }
    }
}
