using namespace System.Net

Function Invoke-AddAlert {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $URL = ($request.headers.'x-ms-original-url').split('/api') | Select-Object -First 1
    $Tenants = $request.body.tenantFilter
    $Table = get-cipptable -TableName 'SchedulerConfig'
    $Results = foreach ($Tenant in $Tenants) {
        try {
            Write-Host "Working on $($Tenant.value) - $($Tenant.fullValue.displayName)"
            $CompleteObject = @{
                tenant       = [string]$($Tenant.value)
                tenantid     = [string]$($Tenant.fullValue.customerId)
                webhookType  = [string]$request.body.logbook.value
                type         = 'webhookcreation'
                RowKey       = "$($Tenant.value)-$($request.body.logbook.value)"
                PartitionKey = 'webhookcreation'
                Configured   = $false
                CIPPURL      = [string]$URL
            }
            Add-CIPPAzDataTableEntity @Table -Entity $CompleteObject -Force
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant.fullValue.defaultDomainName -message "Successfully added Audit Log Webhook for $($Tenant.fullValue.displayName) to queue." -Sev 'Info'
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant.fullValue.defaultDomainName -message "Failed to add Audit Log Webhook for $($Tenant.fullValue.displayName) to queue" -Sev 'Error'
            "Failed to add Alert for for $($Tenant) to queue $($_.Exception.message)"
        }
    }
    $Conditions = $request.body.conditions | ConvertTo-Json -Compress -Depth 10 | Out-String
    $TenantsJson = $Tenants | ConvertTo-Json -Compress -Depth 10 | Out-String
    $Actions = $request.body.actions | ConvertTo-Json -Compress -Depth 10 | Out-String
    $CompleteObject = @{
        Tenants      = [string]$TenantsJson
        Conditions   = [string]$Conditions
        Actions      = [string]$Actions
        type         = $request.body.logbook.value
        RowKey       = [string](New-Guid)
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