function Remove-CIPPMigrationAppSetting {
    <#
    .SYNOPSIS
        Removes an app setting from the current App Service via ARM.
    .DESCRIPTION
        Reads the current app settings from ARM, removes the specified key,
        and writes the updated settings back. Uses the managed identity for
        authentication. Silently returns $false when not running in App Service.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SettingName
    )

    $SiteName = $env:WEBSITE_SITE_NAME
    $ResourceGroup = $env:WEBSITE_RESOURCE_GROUP
    $SubscriptionId = if ($env:WEBSITE_OWNER_NAME) { ($env:WEBSITE_OWNER_NAME -split '\+')[0] } else { $null }

    if (-not $SiteName -or -not $ResourceGroup -or -not $SubscriptionId) {
        Write-Information "[Migration] Not running in App Service — cannot remove app setting '$SettingName'"
        return $false
    }

    if (-not $env:IDENTITY_ENDPOINT -or -not $env:IDENTITY_HEADER) {
        Write-Information "[Migration] No managed identity available — cannot remove app setting '$SettingName'"
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

    # Read current app settings
    $CurrentSettings = Invoke-RestMethod -Uri "$BaseUri/config/appsettings/list?api-version=2024-11-01" -Method Post -Headers @{ Authorization = "Bearer $ArmToken" }
    $MergedSettings = @{}
    if ($CurrentSettings.properties) {
        $CurrentSettings.properties.PSObject.Properties | ForEach-Object { $MergedSettings[$_.Name] = $_.Value }
    }

    if (-not $MergedSettings.ContainsKey($SettingName)) {
        Write-Information "[Migration] App setting '$SettingName' not found — nothing to remove"
        return $true
    }

    $MergedSettings.Remove($SettingName)

    $SettingsBody = @{ properties = $MergedSettings } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$BaseUri/config/appsettings?api-version=2024-11-01" -Method Put -Headers $ArmHeaders -Body $SettingsBody

    Write-Information "[Migration] Removed app setting '$SettingName'"
    Write-LogMessage -API 'SSO-Migration' -message "Removed app setting '$SettingName' after successful SSO migration" -sev Info
    return $true
}
