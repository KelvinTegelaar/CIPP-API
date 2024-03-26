using namespace System.Net

Function Invoke-RemoveWebhookAlert {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Table = get-cipptable -TableName 'SchedulerConfig'

    try {
        $WebhookTable = Get-CIPPTable -TableName SchedulerConfig 
        $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq 'WebhookAlert'" | Where-Object -Property Tenant -EQ $Request.query.TenantFilter
        Write-Host "The webhook count is $($WebhookRow.count)"
        if ($WebhookRow.count -gt 1) {
            $Entity = $WebhookRow | Where-Object -Property RowKey -EQ $Request.query.ID
            Remove-AzDataTableEntity @WebhookTable -Entity $Entity | Out-Null
            $Results = "Removed Alert Rule for $($Request.query.TenantFilter)"
        } else {
            if ($Request.query.TenantFilter -eq 'AllTenants') {
                $Tenants = Get-Tenants -IncludeAll -IncludeErrors | Select-Object -ExpandProperty defaultDomainName
                try {
                    $CompleteObject = @{
                        tenant       = 'AllTenants'
                        type         = 'webhookcreation'
                        RowKey       = 'AllTenantsWebhookCreation'
                        PartitionKey = 'webhookcreation'
                    }
                    Remove-AzDataTableEntity @Table -Entity $CompleteObject -ErrorAction SilentlyContinue | Out-Null
                } catch {
                    #
                }
            } else {
                $Tenants = $Request.query.TenantFilter
            }
    
            $Results = foreach ($Tenant in $Tenants) {
                Remove-CIPPGraphSubscription -TenantFilter $Tenant -Type 'AuditLog'
                $Entity = $WebhookRow | Where-Object -Property RowKey -EQ $Request.query.ID
                Remove-AzDataTableEntity @WebhookTable -Entity $Entity | Out-Null
                "Removed Alert Rule for $($Request.query.TenantFilter)"
            }
        }
        $body = [pscustomobject]@{'Results' = $Results }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to remove webhook alert. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed to remove webhook alert: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}