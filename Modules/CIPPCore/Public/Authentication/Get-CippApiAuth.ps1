function Get-CippApiAuth {
    param(
        [string]$RGName,
        [string]$FunctionAppName
    )

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
