using namespace System.Net

Function Invoke-AddAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenants = $request.body.tenantFilter
    $Conditions = $request.body.conditions | ConvertTo-Json -Compress -Depth 10 | Out-String
    $TenantsJson = $Tenants | ConvertTo-Json -Compress -Depth 10 | Out-String
    $Actions = $request.body.actions | ConvertTo-Json -Compress -Depth 10 | Out-String
    $RowKey = $Request.body.RowKey ? $Request.body.RowKey : (New-Guid).ToString()
    $CompleteObject = @{
        Tenants      = [string]$TenantsJson
        Conditions   = [string]$Conditions
        Actions      = [string]$Actions
        type         = $request.body.logbook.value
        RowKey       = $RowKey
        PartitionKey = 'Webhookv2'
    }
    $WebhookTable = get-cipptable -TableName 'WebhookRules'
    Add-CIPPAzDataTableEntity @WebhookTable -Entity $CompleteObject -Force
    $Results = "Added Audit Log Alert for $($Tenants.count) tenants. It may take up to four hours before Microsoft starts delivering these alerts."
    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
