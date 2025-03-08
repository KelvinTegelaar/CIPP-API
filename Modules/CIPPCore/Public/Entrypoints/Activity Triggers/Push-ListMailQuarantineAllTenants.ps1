function Push-ListMailQuarantineAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $domainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName cacheQuarantineMessages

    try {
        $quarantineMessages = New-ExoRequest -tenantid $domainName -cmdlet 'Get-QuarantineMessage' -cmdParams @{ 'PageSize' = 1000 }
        $GraphRequest = foreach ($message in $quarantineMessages) {
            $GUID = (New-Guid).Guid
            $messageData = @{
                QuarantineMessage = [string]($message | ConvertTo-Json -Depth 10)
                RowKey            = [string]$GUID
                PartitionKey      = 'QuarantineMessage'
                Tenant            = [string]$domainName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $messageData -Force | Out-Null
        }
    } catch {
        $GUID = (New-Guid).Guid
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
            RowKey            = [string]$GUID
            PartitionKey      = 'QuarantineMessage'
            Tenant            = [string]$domainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $messageData -Force | Out-Null
    }
}
