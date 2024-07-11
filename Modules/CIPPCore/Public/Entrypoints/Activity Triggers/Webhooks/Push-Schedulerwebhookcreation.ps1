function Push-Schedulerwebhookcreation {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $item
    )
    $Table = Get-CIPPTable -TableName 'SchedulerConfig'
    $WebhookTable = Get-CIPPTable -TableName 'webhookTable'

    #Write-Information ($item | ConvertTo-Json -Depth 10)
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($item.SchedulerRow)'"
    if (!$Row) {
        Write-Host "No row found for $($item.SchedulerRow). Full received item was $($item | ConvertTo-Json)"
        return
    } else {
        if ($Row.tenantid -eq 'AllTenants') {
            $Tenants = (Get-Tenants).defaultDomainName
        } else {
            $Tenants = (Get-Tenants | Where-Object { $_.customerId -eq $Row.tenantid }).defaultDomainName
        }
        foreach ($Tenant in $Tenants) {
            Write-Host "Working on $Tenant - $($Row.tenantid)"
            #use the queueitem to see if we already have a webhook for this tenant + webhooktype. If we do, delete this row from SchedulerConfig.
            $Webhook = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq '$Tenant' and Version eq '3' and Resource eq '$($Row.webhookType)'"
            if ($Webhook) {
                Write-Host "Found existing webhook for $Tenant - $($Row.webhookType)"
                if ($Row.tenantid -ne 'AllTenants') {
                    Remove-AzDataTableEntity @Table -Entity $Row
                }
            } else {
                Write-Host "No existing webhook for $Tenant - $($Row.webhookType) - Time to create."
                try {
                    $NewSub = New-CIPPGraphSubscription -TenantFilter $Tenant -EventType $Row.webhookType -auditLogAPI $true
                    if ($NewSub.Success -and $Row.tenantid -ne 'AllTenants') {
                        Remove-AzDataTableEntity @Table -Entity $Row
                    } else {
                        Write-Host "Failed to create webhook for $Tenant - $($Row.webhookType) - $($_.Exception.Message)"
                    }
                } catch {
                    Write-Host "Failed to create webhook for $Tenant - $($Row.webhookType): $($_.Exception.Message)"
                }

            }
        }
    }

}