using namespace System.Net
param($Request, $TriggerMetadata)

$Subscription = ($ENV:WEBSITE_OWNER_NAME).split('+') | Select-Object -First 1
if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
    $AzSession = Connect-AzAccount -Identity -Subscription $Subscription
}

if ($Request.body.TZ) {
    Update-AzFunctionAppSetting -Name $ENV:WEBSITE_SITE_NAME -ResourceGroupName $ENV:Website_Resource_Group -AppSetting @{"WEBSITE_TIME_ZONE" = "$($request.body.TZ)" }       
    $body = @{"Results" = "Set timezone to $($request.body.TZ)" }
}
else {
    $body = @{"Results" = $ENV:WEBSITE_TIME_ZONE }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
