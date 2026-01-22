function Invoke-ExecBackendURLs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Subscription = Get-CIPPAzFunctionAppSubId
    $SWAName = $env:WEBSITE_SITE_NAME -replace 'cipp', 'CIPP-SWA-'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $Owner = $env:WEBSITE_OWNER_NAME
    if ($env:WEBSITE_SKU -ne 'FlexConsumption' -and $Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
        $RGName = $Matches.RGName
    } else {
        $RGName = $env:WEBSITE_RESOURCE_GROUP
    }

    $results = [PSCustomObject]@{
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
        Hosted             = $env:CIPP_HOSTED -eq 'true' ?? $false
        OS                 = $IsLinux ? 'Linux' : 'Windows'
        SKU                = $env:WEBSITE_SKU
        Timezone           = $env:WEBSITE_TIME_ZONE ?? 'UTC'
        BusinessHoursStart = $env:CIPP_BUSINESS_HOURS_START ?? '09:00'
        BusinessHoursEnd   = $env:CIPP_BUSINESS_HOURS_END ?? '17:00'
    }


    $body = @{Results = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [httpstatusCode]::OK
            Body       = $body
        })

}
