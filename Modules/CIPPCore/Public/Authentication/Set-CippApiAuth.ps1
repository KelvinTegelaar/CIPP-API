function Set-CippApiAuth {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RGName,
        [string]$FunctionAppName,
        [string]$TenantId,
        [string[]]$ClientIds
    )

    # Resolve subscription ID via helper (managed identity environment assumed for ARM).
    $SubscriptionId = Get-CIPPAzFunctionAppSubId

    # Get auth settings via ARM REST (managed identity)
    $getUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($FunctionAppName)/config/authsettingsV2/list?api-version=2020-06-01"
    $resp = New-CIPPAzRestRequest -Uri $getUri -Method 'GET'
    $AuthSettings = $resp | Select-Object -ExpandProperty Content -ErrorAction SilentlyContinue
    if ($AuthSettings -is [string]) { $AuthSettings = $AuthSettings | ConvertFrom-Json }
    else { $AuthSettings = $resp }

    Write-Information "AuthSettings: $($AuthSettings | ConvertTo-Json -Depth 10)"

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
        # Update auth settings via ARM REST
        $putUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($FunctionAppName)/config/authsettingsV2?api-version=2020-06-01"
        $null = New-CIPPAzRestRequest -Uri $putUri -Method 'PUT' -Body $AuthSettings -ContentType 'application/json'
    }

    if ($PSCmdlet.ShouldProcess('Update allowed tenants')) {
        $null = Update-CIPPAzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $RGName -AppSetting @{ 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS' = $TenantId }
    }
}
