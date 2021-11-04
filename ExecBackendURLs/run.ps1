using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

$Subscription = ($ENV:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1
$SWAName = $ENV:Website_SITE_NAME -replace "cipp", "CIPP-SWA-"
# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$results = @"
<h1>Resource Group </h1><br><br>

<a href="https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/overview">Resource group</a><br>
<a href="https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.KeyVault/vaults/$($ENV:WEBSITE_SITE_NAME)/secrets">Keyvault (Password storage)</a><br>
<br><br><h1>Function app </h1><br><br>
<a href="https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/appServices">Function Application (Overview) </a><br>
<a href="https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/configuration">Function Application (Configuration) </a><br>
<a href="https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/sites/$($ENV:WEBSITE_SITE_NAME)/vstscd">Function Application (Deployment Center)</a><br>
<br><br><h1>Static Web App </h1><br><br>
<a href="https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/staticSites/$SWAName/customDomains">Static Web App (Custom Domains)</a><br>
<a href="https://portal.azure.com/#@Go/resource/subscriptions/$Subscription/resourceGroups/$ENV:Website_Resource_Group/providers/Microsoft.Web/staticSites/$SWAName/customDomains">Static Web App (Role Management)</a><br>


"@


$body = @{Results = $Results } 

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [httpstatusCode]::OK
        Body       = $body
    })
