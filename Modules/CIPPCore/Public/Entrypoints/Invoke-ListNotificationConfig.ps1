using namespace System.Net

Function Invoke-ListNotificationConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -TableName SchedulerConfig
    $Filter = "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'"
    $Config = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    if ($Config) {
        $Config = $Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10 -AsHashtable
    } else {
        $Config = @{}
    }
    #$config | Add-Member -NotePropertyValue @() -NotePropertyName 'logsToInclude' -Force
    $config.logsToInclude = @(([pscustomobject]$config | Select-Object * -ExcludeProperty schedule, type, tenantid, onepertenant, sendtoIntegration, partitionkey, rowkey, tenant, ETag, email, logsToInclude, Severity, Alert, Info, Error, timestamp, webhook, includeTenantId).psobject.properties.name)
    if (!$config.logsToInclude) {
        $config.logsToInclude = @('None')
    }
    if (!$config.Severity) {
        $config.Severity = @('Alert')
    } else {
        $config.Severity = $config.Severity -split ','
    }
    $body = [PSCustomObject]$Config

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
