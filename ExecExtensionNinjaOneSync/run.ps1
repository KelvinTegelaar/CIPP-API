using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$Table = Get-CIPPTable -TableName NinjaOneSettings

$CIPPMapping = Get-CIPPTable -TableName CippMapping
$Filter = "PartitionKey eq 'NinjaOrgsMapping'"
$TenantsToProcess = Get-AzDataTableEntity @CIPPMapping -Filter $Filter | Where-Object { $Null -ne $_.NinjaOne -and $_.NinjaOne -ne '' }

foreach ($Tenant in $TenantsToProcess) {
    Push-OutputBinding -Name NinjaProcess -Value @{
        'NinjaAction' = 'SyncTenant'
        'MappedTenant' = $Tenant
    }

}

$AddObject = @{
    PartitionKey   = 'NinjaConfig'
    RowKey         = 'NinjaLastRunTime'
    'SettingValue' = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffK")
}

Add-AzDataTableEntity @Table -Entity $AddObject -Force

Write-LogMessage -API 'NinjaOneAutoMap_Queue' -user 'CIPP' -message "NinjaOne Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" -Sev 'Info' 

$Results = [pscustomobject]@{"Results" = "NinjaOne Synchronization Queued for $(($TenantsToProcess | Measure-Object).count) Tenants" }

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    }) -clobber