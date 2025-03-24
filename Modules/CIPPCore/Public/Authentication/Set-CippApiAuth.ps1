function Set-CippApiAuth {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RGName,
        [string]$FunctionAppName,
        [string]$TenantId,
        [string[]]$ClientIds
    )

    if ($env:MSI_SECRET) {
        Disable-AzContextAutosave -Scope Process | Out-Null
        $null = Connect-AzAccount -Identity
        $SubscriptionId = $ENV:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
        $Context = Set-AzContext -SubscriptionId $SubscriptionId
    } else {
        $Context = Get-AzContext
    }
    # Get subscription id
    $SubscriptionId = $Context.Subscription.Id

    # Get auth settings
    $AuthSettings = Invoke-AzRestMethod -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($FunctionAppName)/config/authsettingsV2/list?api-version=2020-06-01" | Select-Object -ExpandProperty Content | ConvertFrom-Json

    # Set allowed audiences
    $AllowedAudiences = foreach ($ClientId in $ClientIds) {
        "api://$ClientId"
    }

    if (!$AllowedAudiences) { $AllowedAudiences = @() }
    if (!$ClientIds) { $ClientIds = @() }

    # Set auth settings

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
        # Update auth settings
        $null = Invoke-AzRestMethod -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($FunctionAppName)/config/authsettingsV2?api-version=2020-06-01" -Method PUT -Payload ($AuthSettings | ConvertTo-Json -Depth 10)
    }

    if ($PSCmdlet.ShouldProcess('Update allowed tenants')) {
        $null = Update-AzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $RGName -AppSetting @{ 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS' = $TenantId }
    }
}
