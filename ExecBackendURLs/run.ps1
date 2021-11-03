using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$Subscription = ($ENV:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1
$SWAName = $ENV:Website_Resource_Group -replace "cipp", "CIPP-SWA-"
# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$results = @"
<h1>Resource Group </h1><br>

Resource group: https://portal.azure.com/#/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/overview <br>
Keyvault (Password storage): https://portal.azure.com/#@limenetworks.nl/resource/subscriptions/$ENV:Website_Resource_Group/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.KeyVault/vaults/$($ENV:WEBSITE_SITE_NAME)/secrets <br>
<h1>Function app </h1><br>
Function Application (Overview): https://portal.azure.com/#@limenetworks.nl/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/appServices <br>
Function Application (Configuration): https://portal.azure.com/#@limenetworks.nl/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/configuration <br>
Function Application (Deployment Center): https://portal.azure.com/#@limenetworks.nl/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/vstscd <br>
<h1>Static Web App </h1><br>
Static Web App (Custom Domains): https://portal.azure.com/#@limenetworks.nl/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/staticSites/$SWAName/customDomains <br>
Static Web App (Role Management): https://portal.azure.com/#@limenetworks.nl/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/staticSites/$SWAName/customDomains <br>


"@


$body = @{Results = $Results } 

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
