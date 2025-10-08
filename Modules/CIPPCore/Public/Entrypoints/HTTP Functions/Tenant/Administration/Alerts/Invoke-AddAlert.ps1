Function Invoke-AddAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
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

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ 'Results' = @($Results) }
        })

}
