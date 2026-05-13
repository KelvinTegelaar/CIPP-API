function Set-CIPPSSOEasyAuth {
    <#
    .SYNOPSIS
        Configures or updates EasyAuth (authsettingsV2) on the current App Service.
    .DESCRIPTION
        Handles both initial EasyAuth setup and ongoing updates. For initial setup,
        creates the full authsettingsV2 config with KV references for the client secret.
        For updates, reads the existing config and patches the issuer URL.
        Also manages the AUTH_SECRET app setting (using KV references) and
        WEBSITE_AUTH_AAD_ALLOWED_TENANTS.
        Only works inside an Azure App Service with a managed identity.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [bool]$MultiTenant,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter()]
        [switch]$UseKvReferences,

        [Parameter()]
        [switch]$ImplicitAuth
    )

    $SiteName = $env:WEBSITE_SITE_NAME
    $ResourceGroup = $env:WEBSITE_RESOURCE_GROUP
    $SubscriptionId = if ($env:WEBSITE_OWNER_NAME) { ($env:WEBSITE_OWNER_NAME -split '\+')[0] } else { $null }

    if (-not $SiteName -or -not $ResourceGroup -or -not $SubscriptionId) {
        Write-Information '[SSO-EasyAuth] Not running in App Service — skipping EasyAuth config'
        return $false
    }

    if (-not $env:IDENTITY_ENDPOINT -or -not $env:IDENTITY_HEADER) {
        Write-Information '[SSO-EasyAuth] No managed identity available — skipping EasyAuth config'
        return $false
    }

    # Get managed identity token for ARM
    $TokenUri = "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com/&api-version=2019-08-01"
    $TokenResponse = Invoke-RestMethod -Uri $TokenUri -Headers @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER } -Method Get
    $ArmToken = $TokenResponse.access_token

    $BaseUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$SiteName"
    $ArmHeaders = @{
        Authorization  = "Bearer $ArmToken"
        'Content-Type' = 'application/json'
    }

    $IssuerUrl = if ($MultiTenant) {
        'https://login.microsoftonline.com/common/v2.0'
    } else {
        "https://login.microsoftonline.com/$TenantId/v2.0"
    }

    # Read current app settings and merge AUTH_SECRET
    $CurrentSettings = Invoke-RestMethod -Uri "$BaseUri/config/appsettings/list?api-version=2024-11-01" -Method Post -Headers @{ Authorization = "Bearer $ArmToken" }
    $MergedSettings = @{}
    if ($CurrentSettings.properties) {
        $CurrentSettings.properties.PSObject.Properties | ForEach-Object { $MergedSettings[$_.Name] = $_.Value }
    }

    # Set AUTH_SECRET as a KV reference when requested (initial setup)
    # Skip for implicit auth (no client secret needed — e.g. central migration app)
    if ($UseKvReferences -and -not $ImplicitAuth) {
        $KV = $env:WEBSITE_DEPLOYMENT_ID
        $VaultName = if ($KV) { ($KV -split '-')[0] } else { $null }
        if ($VaultName) {
            $MergedSettings['AUTH_SECRET'] = "@Microsoft.KeyVault(VaultName=$VaultName;SecretName=SSOAppSecret)"
        }
    }

    # Always remove WEBSITE_AUTH_AAD_ALLOWED_TENANTS — we rely on the issuer URL
    # for tenant restriction ("Use default restrictions based on issuer" in the portal).
    # Multi-tenant uses common/v2.0 issuer, single-tenant uses {tenantId}/v2.0.
    $MergedSettings.Remove('WEBSITE_AUTH_AAD_ALLOWED_TENANTS')

    $SettingsBody = @{ properties = $MergedSettings } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$BaseUri/config/appsettings?api-version=2024-11-01" -Method Put -Headers $ArmHeaders -Body $SettingsBody

    # Determine if we can read-modify-write (update) or need a full overwrite (initial setup)
    if (-not $UseKvReferences -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
        # Read-modify-write: only patch the issuer URL, preserving existing allowedAudiences,
        # allowedApplications, excludedPaths, tokenStore, etc.
        $Current = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -AsHashtable -Depth 20
        $ArmPayload = @{ properties = $Current }

        # Safely navigate to AAD registration
        if (-not $Current.ContainsKey('identityProviders') -or $null -eq $Current.identityProviders) { $Current.identityProviders = @{} }
        if (-not $Current.identityProviders.ContainsKey('azureActiveDirectory') -or $null -eq $Current.identityProviders.azureActiveDirectory) { $Current.identityProviders.azureActiveDirectory = @{} }
        $AAD = $Current.identityProviders.azureActiveDirectory

        if (-not $AAD.ContainsKey('registration') -or $null -eq $AAD.registration) { $AAD.registration = @{} }
        $AAD.registration.openIdIssuer = $IssuerUrl

        # Ensure the SSO app's own clientId is always in allowedAudiences and allowedApplications
        if (-not $AAD.ContainsKey('validation') -or $null -eq $AAD.validation) { $AAD.validation = @{} }

        $ExistingAudiences = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($AAD.validation.allowedAudiences) {
            foreach ($a in $AAD.validation.allowedAudiences) { [void]$ExistingAudiences.Add($a) }
        }
        [void]$ExistingAudiences.Add("api://$AppId")
        $AAD.validation.allowedAudiences = @($ExistingAudiences)

        if (-not $AAD.validation.ContainsKey('defaultAuthorizationPolicy') -or $null -eq $AAD.validation.defaultAuthorizationPolicy) {
            $AAD.validation.defaultAuthorizationPolicy = @{}
        }
        $ExistingApps = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($AAD.validation.defaultAuthorizationPolicy.allowedApplications) {
            foreach ($a in $AAD.validation.defaultAuthorizationPolicy.allowedApplications) { [void]$ExistingApps.Add($a) }
        }
        [void]$ExistingApps.Add($AppId)
        $AAD.validation.defaultAuthorizationPolicy.allowedApplications = @($ExistingApps)

        if (-not $AAD.validation.defaultAuthorizationPolicy.ContainsKey('allowedPrincipals')) {
            $AAD.validation.defaultAuthorizationPolicy.allowedPrincipals = @{}
        }

        $AuthConfig = $ArmPayload | ConvertTo-Json -Depth 20
        Write-Information "[SSO-EasyAuth] Read-modify-write: patching issuer to $IssuerUrl (preserving $(($ExistingAudiences).Count) audiences, $(($ExistingApps).Count) allowed apps)"
    } else {
        # Full overwrite: initial setup — build the entire authsettingsV2 from scratch
        $AuthConfig = @{
            properties = @{
                platform         = @{ enabled = $true }
                globalValidation = @{
                    unauthenticatedClientAction = 'RedirectToLoginPage'
                    redirectToProvider           = 'azureactivedirectory'
                    excludedPaths               = @(
                        '/api/Public*'
                        '/api/setup/health'
                    )
                }
                identityProviders = @{
                    azureActiveDirectory = @{
                        enabled      = $true
                        registration = $(if ($ImplicitAuth) {
                            @{
                                clientId     = $AppId
                                openIdIssuer = $IssuerUrl
                            }
                        } else {
                            @{
                                clientId               = $AppId
                                clientSecretSettingName = 'AUTH_SECRET'
                                openIdIssuer           = $IssuerUrl
                            }
                        })
                        validation   = @{
                            allowedAudiences           = @("api://$AppId")
                            defaultAuthorizationPolicy = @{
                                allowedPrincipals   = @{}
                                allowedApplications = @($AppId)
                            }
                        }
                    }
                }
                login = @{
                    tokenStore = @{
                        enabled                    = $true
                        tokenRefreshExtensionHours = 72
                    }
                }
            }
        } | ConvertTo-Json -Depth 20
    }

    Invoke-RestMethod -Uri "$BaseUri/config/authsettingsV2?api-version=2020-06-01" -Method Put -Headers $ArmHeaders -Body $AuthConfig

    Write-Information "[SSO-EasyAuth] Configured EasyAuth: appId=$AppId, issuer=$IssuerUrl, multiTenant=$MultiTenant"
    Write-LogMessage -API 'SSO-EasyAuth' -message "EasyAuth configured: appId=$AppId, issuer=$IssuerUrl" -sev Info
    return $true
}
