function Get-CippApiAuth {
    param(
        [string]$RGName,
        [string]$FunctionAppName
    )

    $AuthSettings = $null

    # When the auth config is available as an env var, use it directly (no ARM call needed)
    if ($env:CIPPNG -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
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

    # Fallback to env var if ARM failed
    if (-not $AuthSettings -and $env:WEBSITE_AUTH_V2_CONFIG_JSON) {
        $AuthSettings = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
    }

    if ($AuthSettings) {
        $AAD = $AuthSettings.identityProviders.azureActiveDirectory
        $Issuer = $AAD.registration.openIdIssuer ?? ''
        $AllowedApps = @($AAD.validation.defaultAuthorizationPolicy.allowedApplications)

        # When SSO EasyAuth is in use, filter out its clientId — the frontend only tracks API clients
        if ($env:CIPPNG) {
            $SSOClientId = $AAD.registration.clientId
            if ($SSOClientId) {
                $AllowedApps = @($AllowedApps | Where-Object { $_ -ne $SSOClientId })
            }
        }

        [PSCustomObject]@{
            ApiUrl    = "https://$($env:WEBSITE_HOSTNAME)"
            TenantID  = $Issuer -replace 'https://sts.windows.net/', '' -replace 'https://login.microsoftonline.com/', '' -replace '/v2.0', ''
            ClientIDs = $AllowedApps
            Enabled   = $AAD.enabled
        }
    } else {
        throw 'No auth settings found'
    }
}
