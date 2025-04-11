function Get-CippApiAuth {
    param(
        [string]$RGName,
        [string]$FunctionAppName
    )

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
    $AuthSettings = Invoke-AzRestMethod -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($FunctionAppName)/config/authsettingsV2/list?api-version=2020-06-01" -ErrorAction Stop | Select-Object -ExpandProperty Content | ConvertFrom-Json

    if ($AuthSettings.properties) {
        [PSCustomObject]@{
            ApiUrl    = "https://$($FunctionAppName).azurewebsites.net"
            TenantID  = $AuthSettings.properties.identityProviders.azureActiveDirectory.registration.openIdIssuer -replace 'https://sts.windows.net/', '' -replace '/v2.0', ''
            ClientIDs = $AuthSettings.properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedApplications
            Enabled   = $AuthSettings.properties.identityProviders.azureActiveDirectory.enabled
        }
    } else {
        throw 'No auth settings found'
    }
}
