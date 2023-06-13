using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$results = try { 
    $Table = Get-CIPPTable -TableName SchedulerConfig
    $SchedulerConfig = @{
        'tenant'            = 'Any'
        'tenantid'          = 'TenantId'
        'type'              = 'CIPPNotifications'
        'schedule'          = 'Every 15 minutes'
        'email'             = "$($Request.Body.Email)"
        'webhook'           = "$($Request.Body.Webhook)"
        'onePerTenant'      = [boolean]$Request.Body.onePerTenant
        'sendtoIntegration' = [boolean]$Request.Body.sendtoIntegration
        'PartitionKey'      = 'CippNotifications'
        'RowKey'            = 'CippNotifications'
    }
    foreach ($logvalue in [pscustomobject]$Request.body.logsToInclude) {
        $SchedulerConfig[([pscustomobject]$logvalue.value)] = $true 
    }


    Add-AzDataTableEntity @Table -Entity $SchedulerConfig -Force | Out-Null
    'Successfully set the configuration'
}
catch {
    "Failed to set configuration: $($_.Exception.message)"
}


$body = [pscustomobject]@{'Results' = $Results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
