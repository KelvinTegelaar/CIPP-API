using namespace System.Net

function Invoke-AddAlert {
    <#
    .SYNOPSIS
    Add an audit log alert for one or more tenants
    
    .DESCRIPTION
    Adds an audit log alert for one or more tenants by creating a webhook rule in the CIPP storage. Supports specifying tenants, conditions, actions, and exclusions.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    
    .NOTES
    Group: Alerts
    Summary: Add Alert
    Description: Adds an audit log alert for one or more tenants by creating a webhook rule in the CIPP storage. Supports specifying tenants, conditions, actions, and exclusions. Alerts may take up to four hours to become active.
    Tags: Alerts,Audit,Webhook,Tenants
    Parameter: tenantFilter (array) [body] - Array of tenant identifiers to apply the alert to
    Parameter: conditions (object) [body] - Conditions for triggering the alert
    Parameter: actions (object) [body] - Actions to perform when the alert is triggered
    Parameter: excludedTenants (array) [body] - Array of tenant identifiers to exclude from the alert
    Parameter: logbook (object) [body] - Logbook type for the alert
    Response: Returns a response object with the following properties:
    Response: - Results (string): Success message
    Response: On success: "Added Audit Log Alert for [count] tenants. It may take up to four hours before Microsoft starts delivering these alerts."
    Error: Returns error details if the operation fails to add the alert.
    Example: {
      "Results": "Added Audit Log Alert for 3 tenants. It may take up to four hours before Microsoft starts delivering these alerts."
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Tenants = $Request.Body.tenantFilter
    $Conditions = $Request.Body.conditions | ConvertTo-Json -Compress -Depth 10 | Out-String
    $TenantsJson = $Tenants | ConvertTo-Json -Compress -Depth 10 | Out-String
    $excludedTenantsJson = $Request.Body.excludedTenants | ConvertTo-Json -Compress -Depth 10 | Out-String
    $Actions = $Request.Body.actions | ConvertTo-Json -Compress -Depth 10 | Out-String
    $RowKey = $Request.Body.RowKey ? $Request.Body.RowKey : (New-Guid).ToString()
    $CompleteObject = @{
        Tenants         = [string]$TenantsJson
        excludedTenants = [string]$excludedTenantsJson
        Conditions      = [string]$Conditions
        Actions         = [string]$Actions
        type            = $Request.Body.logbook.value
        RowKey          = $RowKey
        PartitionKey    = 'Webhookv2'
    }
    $WebhookTable = Get-CippTable -TableName 'WebhookRules'
    Add-CIPPAzDataTableEntity @WebhookTable -Entity $CompleteObject -Force
    $Results = "Added Audit Log Alert for $($Tenants.count) tenants. It may take up to four hours before Microsoft starts delivering these alerts."

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ 'Results' = @($Results) }
        })

}
