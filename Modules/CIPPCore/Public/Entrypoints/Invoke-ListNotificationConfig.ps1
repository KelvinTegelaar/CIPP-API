using namespace System.Net

function Invoke-ListNotificationConfig {
    <#
    .SYNOPSIS
    List CIPP notification configuration settings
    
    .DESCRIPTION
    Retrieves CIPP notification configuration settings from the SchedulerConfig table including email, webhook, and severity settings
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
        
    .NOTES
    Group: Notifications
    Summary: List Notification Config
    Description: Retrieves CIPP notification configuration settings from the SchedulerConfig table including email, webhook, severity settings, and logs to include in notifications
    Tags: Notifications,Configuration,Settings
    Response: Returns a notification configuration object with the following properties:
    Response: - email (string): Email address for notifications
    Response: - webhook (string): Webhook URL for notifications
    Response: - onepertenant (boolean): Whether to send one notification per tenant
    Response: - sendtoIntegration (boolean): Whether to send to integration
    Response: - logsToInclude (array): Array of log types to include in notifications
    Response: - Severity (array): Array of severity levels to include (Alert, Info, Error)
    Response: - schedule (string): Notification schedule
    Response: - type (string): Notification type
    Example: {
      "email": "admin@contoso.com",
      "webhook": "https://webhook.office.com/webhookb2/...",
      "onepertenant": true,
      "sendtoIntegration": false,
      "logsToInclude": ["AuditLogs", "SignInLogs", "DirectoryLogs"],
      "Severity": ["Alert", "Error"],
      "schedule": "daily",
      "type": "email"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Table = Get-CIPPTable -TableName SchedulerConfig
    $Filter = "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'"
    $Config = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    if ($Config) {
        $Config = $Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json -Depth 10 -AsHashtable
    }
    else {
        $Config = @{}
    }
    #$config | Add-Member -NotePropertyValue @() -NotePropertyName 'logsToInclude' -Force
    $config.logsToInclude = @(([pscustomobject]$config | Select-Object * -ExcludeProperty schedule, type, tenantid, onepertenant, sendtoIntegration, partitionkey, rowkey, tenant, ETag, email, logsToInclude, Severity, Alert, Info, Error, timestamp, webhook, includeTenantId).psobject.properties.name)
    if (!$config.logsToInclude) {
        $config.logsToInclude = @('None')
    }
    if (!$config.Severity) {
        $config.Severity = @('Alert')
    }
    else {
        $config.Severity = $config.Severity -split ','
    }
    $body = [PSCustomObject]$Config

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
