using namespace System.Net

Function Invoke-RemoveWebhookAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $WebhookTable = Get-CIPPTable -TableName 'SchedulerConfig'
        $WebhookRow = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq 'WebhookAlert'" | Where-Object -Property Tenant -EQ $Request.query.TenantFilter
        Write-Host "The webhook count is $($WebhookRow.count)"
        if ($WebhookRow.count -gt 1) {
            $Entity = $WebhookRow | Where-Object -Property RowKey -EQ $Request.query.ID
            Remove-CIPPAzDataTableEntity -Force @WebhookTable -Entity $Entity | Out-Null
            $Results = "Removed Alert Rule for $($Request.query.TenantFilter)"
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Request.query.TenantFilter -message $Results -Sev 'Info'
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
                    Remove-CIPPAzDataTableEntity -Force @Table -Entity $CompleteObject -ErrorAction SilentlyContinue | Out-Null
                } catch {
                    Write-LogMessage -headers $Request.Headers -API $APIName -tenant 'Global' -message "Failed to remove webhook for AllTenants. $($_.Exception.Message)" -Sev 'Error'
                }
            } else {
                $Tenants = $Request.query.TenantFilter
            }

            $Results = foreach ($Tenant in $Tenants) {
                Remove-CIPPGraphSubscription -TenantFilter $Tenant -Type 'AuditLog'
                $Entity = $WebhookRow | Where-Object -Property RowKey -EQ $Request.query.ID
                Remove-CIPPAzDataTableEntity -Force @WebhookTable -Entity $Entity | Out-Null
                $Message = "Removed Alert Rule for $($Request.query.TenantFilter)"
                Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Info'
                $Message
            }
        }
        $body = [pscustomobject]@{'Results' = $Results }
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant 'Global' -message "Failed to remove webhook alert. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed to remove webhook alert: $($_.Exception.Message)" }
    }

    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        }
}
