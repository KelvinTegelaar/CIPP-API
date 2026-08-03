function Set-CippApiAuth {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RGName,
        [string]$FunctionAppName,
        [string]$TenantId,
        [string[]]$ClientIds,
        [string[]]$McpClientIds
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
    $AllowedAudiences = [System.Collections.Generic.List[string]]::new()
    foreach ($ClientId in @($ClientIds)) {
        if (-not [string]::IsNullOrEmpty($ClientId)) {
            $AllowedAudiences.Add("api://$ClientId")
        }
    }

    # MCP resource clients also accept tokens whose audience is the host-based identifier URI or
    # the bare appId (v2 tokens), so MCP connectors validate against EasyAuth.
    if ($McpClientIds -and $env:WEBSITE_HOSTNAME) {
        $AllowedAudiences.Add("https://$($env:WEBSITE_HOSTNAME)")
        $AllowedAudiences.Add("https://$($env:WEBSITE_HOSTNAME)/api/ExecMcp")
        foreach ($McpId in @($McpClientIds)) {
            if (-not [string]::IsNullOrEmpty($McpId)) {
                $AllowedAudiences.Add($McpId)
            }
        }
    }

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
