function Push-ListMailQuarantineAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $domainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName cacheQuarantineMessages
    Write-Host "PowerShell queue trigger function processed work item: $($Tenant.defaultDomainName)"

    try {
        $quarantineMessages = New-ExoRequest -tenantid $domainName -cmdlet 'Get-QuarantineMessage' -cmdParams @{ 'PageSize' = 1000 } | Select-Object -ExcludeProperty *data.type*
        $GraphRequest = foreach ($message in $quarantineMessages) {
            $messageData = @{
                QuarantineMessage = [string]($message | ConvertTo-Json -Depth 10 -Compress)
                RowKey            = [string](New-Guid).Guid
                PartitionKey      = 'QuarantineMessage'
                Tenant            = [string]$domainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $messageData -Force | Out-Null
        }
    } catch {
        $errorData = ConvertTo-Json -InputObject @{
            Identity         = $null
            ReceivedTime     = (Get-Date).ToString('s')
            SenderAddress    = 'CIPP Error'
            RecipientAddress = 'N/A'
            Subject          = "Could not connect to Tenant: $($_.Exception.Message)"
            Size             = 0
            Type             = 'Error'
            QuarantineReason = 'ConnectionError'
        }
        $messageData = @{
            QuarantineMessage = [string]$errorData
            RowKey            = [string]$domainName
            PartitionKey      = 'QuarantineMessage'
            Tenant            = [string]$domainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $messageData -Force | Out-Null
    }
}
