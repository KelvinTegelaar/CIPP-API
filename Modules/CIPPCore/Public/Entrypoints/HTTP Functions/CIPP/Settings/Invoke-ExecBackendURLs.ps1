using namespace System.Net

Function Invoke-ExecBackendURLs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Subscription = ($env:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1
    $SWAName = $env:WEBSITE_SITE_NAME -replace 'cipp', 'CIPP-SWA-'

    $results = [PSCustomObject]@{
        ResourceGroup      = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$env:WEBSITE_RESOURCE_GROUP/overview"
        KeyVault           = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$env:WEBSITE_RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$($env:WEBSITE_SITE_NAME)/secrets"
        FunctionApp        = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$env:WEBSITE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$($env:WEBSITE_SITE_NAME)/appServices"
        FunctionConfig     = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$env:WEBSITE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$($env:WEBSITE_SITE_NAME)/configuration"
        FunctionDeployment = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$env:WEBSITE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$($env:WEBSITE_SITE_NAME)/vstscd"
        SWADomains         = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$env:WEBSITE_RESOURCE_GROUP/providers/Microsoft.Web/staticSites/$SWAName/customDomains"
        SWARoles           = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$env:WEBSITE_RESOURCE_GROUP/providers/Microsoft.Web/staticSites/$SWAName/roleManagement"
        Subscription       = $Subscription
        RGName             = $env:WEBSITE_RESOURCE_GROUP
        FunctionName       = $env:WEBSITE_SITE_NAME
        SWAName            = $SWAName
    }


    $body = @{Results = $Results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [httpstatusCode]::OK
            Body       = $body
        })

}
