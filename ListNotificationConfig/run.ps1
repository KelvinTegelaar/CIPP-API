﻿using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

$Table = Get-CIPPTable -TableName SchedulerConfig
$Filter = "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'"
$Config = Get-AzDataTableEntity @Table -Filter $Filter | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10
$config | Add-Member -NotePropertyValue @() -NotePropertyName 'logsToInclude' -Force
$config.logsToInclude = @(([pscustomobject]$config | Select-Object * -ExcludeProperty schedule, type, tenantid, onepertenant, sendtoIntegration, partitionkey, rowkey, tenant, ETag, email, logsToInclude, Severity, Alert, Info, Error, timestamp, webhook).psobject.properties.name)
if (!$config.logsToInclude) {
    $config.logsToInclude = @('None')
}
if (!$config.Severity) {
    $config.Severity = @('Alert')
}
else {
    $config.Severity = $config.Severity -split ','
}
$body = $Config

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
