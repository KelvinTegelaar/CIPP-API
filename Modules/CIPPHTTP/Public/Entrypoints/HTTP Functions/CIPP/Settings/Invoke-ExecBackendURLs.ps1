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

    try {
        $RGName = Get-CIPPFunctionAppResourceGroup
    } catch {
        Write-Information "Could not determine resource group: $($_.Exception.Message)"
        $RGName = $null
    }

    $results = @{
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
    }

    $results.Timezone = $env:CIPP_TIMEZONE ?? 'UTC'

    $body = @{Results = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [httpstatusCode]::OK
            Body       = $body
        })

}
