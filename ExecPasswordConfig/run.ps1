using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$Table = Get-CIPPTable -TableName Settings
$PasswordType = (Get-AzDataTableEntity @Table)

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$results = try { 
    if ($Request.Query.List) {
        @{ passwordType = $PasswordType.passwordType }
    }
    else {
        $SchedulerConfig = @{
            'passwordType'  = "$($Request.Body.passwordType)"
            'passwordCount' = "12"
            'PartitionKey'  = 'settings'
            'RowKey'        = 'settings'
        }

        Add-AzDataTableEntity @Table -Entity $SchedulerConfig -Force | Out-Null
        'Successfully set the configuration'
    }
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
