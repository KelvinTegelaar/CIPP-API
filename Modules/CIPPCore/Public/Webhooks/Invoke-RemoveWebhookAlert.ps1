using namespace System.Net

function Invoke-RemoveWebhookAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $WebhookTable = Get-CIPPTable -TableName 'SchedulerConfig'
        $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq 'WebhookAlert'" | Where-Object -Property Tenant -EQ $Request.Query.TenantFilter
        Write-Host "The webhook count is $($WebhookRow.count)"
        if ($WebhookRow.count -gt 1) {
            $Entity = $WebhookRow | Where-Object -Property RowKey -EQ $Request.Query.ID
            Remove-AzDataTableEntity -Force @WebhookTable -Entity $Entity | Out-Null
            $Results = "Removed Alert Rule for $($Request.Query.TenantFilter)"
        } else {
            if ($Request.Query.TenantFilter -eq 'AllTenants') {
                $Tenants = Get-Tenants -IncludeAll -IncludeErrors | Select-Object -ExpandProperty defaultDomainName
                try {
                    $CompleteObject = @{
                        tenant       = 'AllTenants'
                        type         = 'webhookcreation'
                        RowKey       = 'AllTenantsWebhookCreation'
                        PartitionKey = 'webhookcreation'
                    }
                    Remove-AzDataTableEntity -Force @Table -Entity $CompleteObject -ErrorAction SilentlyContinue | Out-Null
                } catch {
                    Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove webhook for AllTenants. $($_.Exception.Message)" -Sev 'Error'
                }
            } else {
                $Tenants = $Request.Query.TenantFilter
            }

            $Results = foreach ($Tenant in $Tenants) {
                Remove-CIPPGraphSubscription -TenantFilter $Tenant -Type 'AuditLog'
                $Entity = $WebhookRow | Where-Object -Property RowKey -EQ $Request.Query.ID
                Remove-AzDataTableEntity -Force @WebhookTable -Entity $Entity | Out-Null
                "Removed Alert Rule for $($Request.Query.TenantFilter)"
            }
        }
        $Body = [pscustomobject]@{'Results' = $Results }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove webhook alert. $($_.Exception.Message)" -Sev 'Error'
        $Body = [pscustomobject]@{'Results' = "Failed to remove webhook alert: $($_.Exception.Message)" }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
