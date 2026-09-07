function Invoke-ExecBackendURLs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    .DESCRIPTION
        Returns Azure portal deep links for the CIPP deployment's own infrastructure (resource group, key vault, the function app or web app, its App Service plan, static web app) plus its subscription, SKU and timezone. Whether the instance is CyberDrain-hosted or CIPP-NG comes from /api/me.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Subscription = Get-CIPPAzFunctionAppSubId
    $SWAName = $env:WEBSITE_SITE_NAME -replace 'cipp', 'CIPP-SWA-'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    try {
        $RGName = Get-CIPPFunctionAppResourceGroup
    } catch {
        Write-Information "Could not determine resource group: $($_.Exception.Message)"
        $RGName = $null
    }

    # The plan's name is only known to ARM. Best effort: local dev and an identity without rights
    # on the site leave the link empty.
    $AppServicePlan = $null
    try {
        $PlanId = [string](Get-CIPPAppServiceSite).Site.properties.serverFarmId
        if ($PlanId) { $AppServicePlan = "https://portal.azure.com/#@/resource$PlanId/overview" }
    } catch {
        Write-Information "Could not resolve the App Service plan: $($_.Exception.Message)"
    }

    $results = @{
        AppServicePlan     = $AppServicePlan
        ResourceGroup      = "https://portal.azure.com/#@/resource/subscriptions/$Subscription/resourceGroups/$RGName/overview"
        KeyVault           = "https://portal.azure.com/#@/resource/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.KeyVault/vaults/$($env:WEBSITE_SITE_NAME)/secrets"
        FunctionApp        = "https://portal.azure.com/#@/resource/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($env:WEBSITE_SITE_NAME)/appServices"
        FunctionConfig     = "https://portal.azure.com/#@/resource/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($env:WEBSITE_SITE_NAME)/configuration"
        FunctionDeployment = "https://portal.azure.com/#@/resource/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$($env:WEBSITE_SITE_NAME)/vstscd"
        SWADomains         = "https://portal.azure.com/#@/resource/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/staticSites/$SWAName/customDomains"
        SWARoles           = "https://portal.azure.com/#@/resource/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/staticSites/$SWAName/roleManagement"
        Subscription       = $Subscription
        RGName             = $RGName
        FunctionName       = $env:WEBSITE_SITE_NAME
        SWAName            = $SWAName
        OS                 = $IsLinux ? 'Linux' : 'Windows'
        SKU                = $env:WEBSITE_SKU
    }

    $results.Timezone = $env:CIPP_TIMEZONE ?? 'UTC'

    $body = @{Results = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [httpstatusCode]::OK
            Body       = $body
        })

}
