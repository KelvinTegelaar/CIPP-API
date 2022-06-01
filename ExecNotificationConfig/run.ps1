using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$results = try { 
    $Table = Get-CIPPTable -TableName SchedulerConfig
    $SchedulerConfig = @{
        'tenant'             = 'Any'
        'tenantid'           = 'TenantId'
        'type'               = 'CIPPNotifications'
        'schedule'           = "Every 15 minutes"
        'email'              = $Request.Body.Email
        'webhook'            = $Request.Body.Webhook
        "removeStandard"     = $Request.Body.removeStandard
        "addStandardsDeploy" = $Request.Body.addStandardsDeploy
        "tokenUpdater"       = $Request.Body.tokenUpdater
        "addPolicy"          = $Request.Body.addPolicy
        "removeUser"         = $Request.Body.removeUser
        "addUser"            = $Request.Body.addUser
        "addChocoApp"        = $Request.Body.addChocoApp
    }
    $TableRow = @{
        table        = $Table
        partitionKey = 'CippNotifications'
        rowKey       = "CippNotifications"
        property     = $SchedulerConfig
    }
    Add-AzTableRow @TableRow -UpdateExisting | Out-Null
    "succesfully set the configuration"
}
catch {
    "Failed to set configuration"
}


$body = [pscustomobject]@{"Results" = $Results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
