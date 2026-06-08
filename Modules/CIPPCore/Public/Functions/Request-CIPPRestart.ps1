function Request-CIPPRestart {
    <#
    .SYNOPSIS
        Requests a graceful application restart.
    .DESCRIPTION
        Attempts to restart the application using the AppLifecycleBridge for a graceful in-process restart.
        Falls back to the Azure ARM REST API if the bridge is unavailable.
    .PARAMETER Reason
        Log message explaining why the restart was requested.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    try {
        $Subscription = Get-CIPPAzFunctionAppSubId
        $SiteName = $env:WEBSITE_SITE_NAME
        $RGName = $env:WEBSITE_RESOURCE_GROUP
        if (-not $RGName) {
            $Owner = $env:WEBSITE_OWNER_NAME
            if ($Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                $RGName = $Matches.RGName
            }
        }
        if (-not ($Subscription -and $RGName -and $SiteName)) {
            throw 'Azure App Service details could not be determined from environment'
        }
        $restartUrl = "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$SiteName/restart?api-version=2024-04-01"
        $null = New-CIPPAzRestRequest -Uri $restartUrl -Method POST
    } catch {
        Write-Information "ARM REST API restart failed, falling back to AppLifecycleBridge: $($_.Exception.Message)"
        [Craft.Services.AppLifecycleBridge]::RequestRestart($Reason)
    }
}
