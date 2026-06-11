function Get-CippApiAuth {
    param(
        [string]$RGName,
        [string]$FunctionAppName
    )

    if ($env:CIPPNG) {
        $AuthSettings = $null

        # When the auth config is available as an env var, use it directly (no ARM call needed)
        if ($env:WEBSITE_AUTH_V2_CONFIG_JSON) {
            $AuthSettings = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
        }

        # Fall back to reading via ARM REST
        if (-not $AuthSettings) {
            $SubscriptionId = Get-CIPPAzFunctionAppSubId
            try {
                $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($FunctionAppName)/config/authsettingsV2/list?api-version=2020-06-01"
                $response = New-CIPPAzRestRequest -Uri $uri -Method POST -ErrorAction Stop
                $AuthSettings = $response.properties
            } catch {
                Write-Warning "Failed to get auth settings via REST: $($_.Exception.Message)"
            }
        }

        if ($AuthSettings) {
            $AAD = $AuthSettings.identityProviders.azureActiveDirectory
            $Issuer = $AAD.registration.openIdIssuer ?? ''
            $AllowedApps = @($AAD.validation.defaultAuthorizationPolicy.allowedApplications)

            # When SSO EasyAuth is in use, filter out its clientId — the frontend only tracks API clients
            $SSOClientId = $AAD.registration.clientId
            if ($SSOClientId) {
                $AllowedApps = @($AllowedApps | Where-Object { $_ -ne $SSOClientId })
            }

            $ExtractedTenantId = $Issuer -replace 'https://sts.windows.net/', '' -replace 'https://login.microsoftonline.com/', '' -replace '/v2.0', ''
            $TenantId = if ($ExtractedTenantId -eq 'common') { $env:TenantID } else { $ExtractedTenantId }

            [PSCustomObject]@{
                ApiUrl    = "https://$($env:WEBSITE_HOSTNAME)"
                TenantID  = $TenantId
                ClientIDs = $AllowedApps
                Enabled   = $AAD.enabled
            }
        } else {
            throw 'No auth settings found'
        }
    } else {
        $SubscriptionId = Get-CIPPAzFunctionAppSubId

        try {
            # Get auth settings via REST
            $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($FunctionAppName)/config/authsettingsV2/list?api-version=2020-06-01"
            $response = New-CIPPAzRestRequest -Uri $uri -Method POST -ErrorAction Stop
            $AuthSettings = $response.properties
        } catch {
            Write-Warning "Failed to get auth settings via REST: $($_.Exception.Message)"
        }

        if (!$AuthSettings -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
            $AuthSettings = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
        }

        if ($AuthSettings) {
            [PSCustomObject]@{
                ApiUrl    = "https://$($env:WEBSITE_HOSTNAME)"
                TenantID  = $AuthSettings.identityProviders.azureActiveDirectory.registration.openIdIssuer -replace 'https://sts.windows.net/', '' -replace '/v2.0', ''
                ClientIDs = $AuthSettings.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedApplications
                Enabled   = $AuthSettings.identityProviders.azureActiveDirectory.enabled
            }
        } else {
            throw 'No auth settings found'
        }
    }
}
