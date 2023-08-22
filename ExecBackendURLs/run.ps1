using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$Subscription = ($ENV:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1
$SWAName = $ENV:Website_SITE_NAME -replace 'cipp', 'CIPP-SWA-'
# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$results = [PSCustomObject]@{
    ResourceGroup      = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/overview"
    KeyVault           = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.KeyVault/vaults/$($ENV:WEBSITE_SITE_NAME)/secrets"
    FunctionApp        = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/appServices"
    FunctionConfig     = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/configuration"
    FunctionDeployment = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/vstscd"
    SWADomains         = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/staticSites/$SWAName/customDomains"
    SWARoles           = "https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/staticSites/$SWAName/Roles"
    Subscription       = $Subscription
    RGName             = $ENV:Website_Resource_Group
    FunctionName       = $ENV:WEBSITE_SITE_NAME
    SWAName            = $SWAName
}


$body = @{Results = $Results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [httpstatusCode]::OK
        Body       = $body
    })
