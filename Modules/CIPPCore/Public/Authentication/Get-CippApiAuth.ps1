function Get-CippApiAuth {
    param(
        [string]$RGName,
        [string]$FunctionAppName
    )

    if ($env:WEBSITE_AUTH_V2_CONFIG_JSON) {
        $AuthSettings = $env:WEBSITE_AUTH_V2_CONFIG_JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
    }

    if (-not $AuthSettings) {
        if ($env:MSI_SECRET) {
            Disable-AzContextAutosave -Scope Process | Out-Null
            $null = Connect-AzAccount -Identity
            $SubscriptionId = $env:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
            $Context = Set-AzContext -SubscriptionId $SubscriptionId
        } else {
            $Context = Get-AzContext
            $SubscriptionId = $Context.Subscription.Id
        }

        # Get auth settings
        $AuthSettings = (Invoke-AzRestMethod -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($FunctionAppName)/config/authsettingsV2/list?api-version=2020-06-01" -ErrorAction Stop | Select-Object -ExpandProperty Content | ConvertFrom-Json).properties
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
