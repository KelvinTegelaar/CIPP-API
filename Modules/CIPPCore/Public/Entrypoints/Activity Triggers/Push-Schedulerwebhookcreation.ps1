function Push-Schedulerwebhookcreation {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $item
    )
    $Table = Get-CIPPTable -TableName 'SchedulerConfig'
    $WebhookTable = Get-CIPPTable -TableName 'WebhookTable'

    $Row = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($item.SchedulerRow)'"
    $Tenant = (Get-Tenants | Where-Object { $_.customerId -eq $Row.tenantid }).defaultDomainName
    Write-Host "Working on  $Tenant - $($Row.tenantid)"
    #use the queueitem to see if we already have a webhook for this tenant + webhooktype. If we do, delete this row from SchedulerConfig.
    $Webhook = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq '$Tenant' and Version eq '2' and Resource eq '$($Row.webhookType)'"
    if ($Webhook) {
        Write-Host "Found existing webhook for $Tenant - $($Row.webhookType)"
        Remove-CIPPAzDataTableEntity @Table -Entity $Row
    } else {
        Write-Host "No existing webhook for $Tenant - $($Row.webhookType) - Time to create."
        try {
            $NewSub = New-CIPPGraphSubscription -TenantFilter $Tenant -EventType $Row.webhookType -BaseURL $Row.CIPPURL -auditLogAPI $true
            if ($NewSub.Success) {
                Remove-CIPPAzDataTableEntity @Table -Entity $Row
            } else {
                Write-Host "Failed to create webhook for $Tenant - $($Row.webhookType) - $($_.Exception.Message)"
                Write-LogMessage -message "Failed to create webhook for $Tenant - $($Row.webhookType)" -Sev 'Error' -LogData $_.Exception
            }
        } catch {
            Write-Host "Failed to create webhook for $Tenant - $($Row.webhookType): $($_.Exception.Message)"
            Write-LogMessage -message "Failed to create webhook for $Tenant - $($Row.webhookType)" -Sev 'Error' -LogData $_.Exception
 
        }

    }
    
}